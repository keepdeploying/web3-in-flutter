#!/usr/bin/env bash
# Builds the Flutter Counter CosmWasm contract, then stores and instantiates
# it on the Osmosis testnet with the public dev wallet. The network is always
# explicit:
#
#   ./deploy.sh osmo-test-5
#
# osmosisd only builds and signs the transactions, offline. Broadcasting goes
# through the chain's REST (LCD) API with Python, because some networks block
# osmosisd's own RPC requests.
#
# Uses its own throwaway keyring in .osmosis-home/ (gitignored).
set -euo pipefail
cd "$(dirname "$0")"

[ "${1:-}" = "osmo-test-5" ] || { echo "Usage: ./deploy.sh osmo-test-5"; exit 1; }
CHAIN_ID=$1
export LCD=https://lcd.osmotest5.osmosis.zone
HOME_DIR="$PWD/.osmosis-home"
KEYS=(--keyring-backend test --home "$HOME_DIR")
WORK=$(mktemp -d)

for tool in cargo wasm-opt osmosisd python3; do
  command -v $tool >/dev/null || { echo "$tool is missing. See README.md for install steps."; exit 1; }
done

echo "1. Testing and building the contract..."
cargo test
cargo wasm
mkdir -p artifacts
wasm-opt -Os --signext-lowering target/wasm32-unknown-unknown/release/flutter_counter.wasm \
  -o artifacts/flutter_counter.wasm
if command -v cosmwasm-check >/dev/null; then cosmwasm-check artifacts/flutter_counter.wasm; fi

echo "2. Importing the dev wallet (m/44'/118'/0'/0/0)..."
osmosisd keys show dev "${KEYS[@]}" >/dev/null 2>&1 \
  || osmosisd keys add dev --recover "${KEYS[@]}" < ../../keys/dev-mnemonic.txt >/dev/null
ADDRESS=$(osmosisd keys show dev -a "${KEYS[@]}")
[ "$ADDRESS" = "osmo1ed3nqhzlm58pzehnajalx4q5wt4zs85p2cud7a" ] || { echo "Unexpected address $ADDRESS"; exit 1; }
echo "   $ADDRESS"

# Prints "<account number> <sequence>" for the dev account.
account() {
  python3 -c '
import json, os, sys, urllib.request
a = json.load(urllib.request.urlopen(os.environ["LCD"] + "/cosmos/auth/v1beta1/accounts/" + sys.argv[1]))["account"]
print(a["account_number"], a["sequence"])' "$ADDRESS"
}

# Simulates, broadcasts and waits for a signed transaction file. Prints the
# value of one event attribute: send_tx <file> <event type> <attribute key>
send_tx() {
  osmosisd tx encode "$1" > "$WORK/tx.b64"
  python3 - "$WORK/tx.b64" "$2" "$3" <<'PY'
import json, os, sys, time, urllib.request
lcd = os.environ["LCD"]
tx_bytes = open(sys.argv[1]).read().strip()
def post(path, body):
    req = urllib.request.Request(lcd + path, data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"})
    return json.load(urllib.request.urlopen(req))
sim = post("/cosmos/tx/v1beta1/simulate", {"tx_bytes": tx_bytes})
print("   simulated gas:", sim["gas_info"]["gas_used"], file=sys.stderr)
res = post("/cosmos/tx/v1beta1/txs", {"tx_bytes": tx_bytes, "mode": "BROADCAST_MODE_SYNC"})["tx_response"]
if res["code"] != 0:
    sys.exit("Rejected: " + res["raw_log"])
print("   tx", res["txhash"], file=sys.stderr)
for _ in range(40):
    time.sleep(3)
    try:
        tx = json.load(urllib.request.urlopen(lcd + "/cosmos/tx/v1beta1/txs/" + res["txhash"]))["tx_response"]
        break
    except Exception:
        pass
else:
    sys.exit("Transaction not found after 2 minutes")
if tx["code"] != 0:
    sys.exit("Failed: " + tx["raw_log"])
for e in tx["events"]:
    if e["type"] == sys.argv[2]:
        for a in e["attributes"]:
            if a["key"] == sys.argv[3]:
                print(a["value"]); sys.exit()
sys.exit("missing event " + sys.argv[2] + "." + sys.argv[3])
PY
}

# Builds a transaction offline and signs it: sign_tx <out file> <osmosisd tx args...>
sign_tx() {
  local out=$1; shift
  read -r ACC SEQ < <(account)
  osmosisd tx "$@" --from dev "${KEYS[@]}" --generate-only --offline \
    --account-number "$ACC" --sequence "$SEQ" > "$WORK/unsigned.json"
  osmosisd tx sign "$WORK/unsigned.json" --from dev "${KEYS[@]}" --chain-id "$CHAIN_ID" \
    --offline --account-number "$ACC" --sequence "$SEQ" --output-document "$out"
}

echo "3. Storing the code on $CHAIN_ID..."
sign_tx "$WORK/store.json" wasm store artifacts/flutter_counter.wasm --gas 4000000 --fees 400000uosmo
CODE_ID=$(send_tx "$WORK/store.json" store_code code_id)
echo "   code ID $CODE_ID"

echo "4. Instantiating..."
sign_tx "$WORK/init.json" wasm instantiate "$CODE_ID" '{}' --label flutter-counter --no-admin \
  --gas 400000 --fees 40000uosmo
CONTRACT=$(send_tx "$WORK/init.json" instantiate _contract_address)

echo
echo "Done on $CHAIN_ID."
echo "Code ID:  $CODE_ID"
echo "Contract: $CONTRACT"
