#!/usr/bin/env bash
# Publishes the Flutter Counter Move package with the public dev wallet.
# The network is always explicit, so nothing ever publishes by accident:
#
#   ./deploy.sh testnet
#   ./deploy.sh local      # a local network started with `sui start --with-faucet`
#
# It uses its own Sui CLI config in .sui-config/ (gitignored), so it never
# touches your personal ~/.sui wallet.
set -euo pipefail
cd "$(dirname "$0")"

BUILD_ARGS=()
case "${1:-}" in
  testnet) RPC=https://fullnode.testnet.sui.io:443 ;;
  # A local network has no published framework of its own, so build against
  # the testnet framework dependencies.
  local) RPC=http://127.0.0.1:9000; BUILD_ARGS=(--build-env testnet) ;;
  *) echo "Usage: ./deploy.sh testnet|local"; exit 1 ;;
esac
NETWORK=$1

command -v sui >/dev/null || {
  echo "The Sui CLI is missing. Install it with one of:"
  echo "  brew install sui"
  echo "  cargo install --locked --git https://github.com/MystenLabs/sui.git --branch testnet sui"
  exit 1
}

export SUI_CONFIG_DIR="$PWD/.sui-config"
mkdir -p "$SUI_CONFIG_DIR"
# The first call creates a config with the standard envs (testnet, devnet,
# mainnet and local at 127.0.0.1:9000).
[ -f "$SUI_CONFIG_DIR/client.yaml" ] || sui client --yes envs >/dev/null 2>&1 || true
sui client switch --env "$NETWORK" >/dev/null

# Stop if the active environment isn't the one asked for.
ACTIVE=$(sui client active-env)
[ "$ACTIVE" = "$NETWORK" ] || { echo "Active Sui env is '$ACTIVE', expected '$NETWORK'. Stopping."; exit 1; }

# Import the dev wallet (path m/44'/784'/0'/0'/0') and make it active.
ADDRESS=0x78c51a7b5ae65f0966b1cad833ee3ef6ededbe9bc6ff4579543c70ff9c67d29e
sui keytool import "$(cat ../../keys/dev-mnemonic.txt)" ed25519 >/dev/null 2>&1 || true
sui client switch --address "$ADDRESS" >/dev/null
echo "Publishing from $ADDRESS to $NETWORK ($RPC)"

sui move test "${BUILD_ARGS[@]}"
if ! sui client publish --gas-budget 200000000 "${BUILD_ARGS[@]}" --json > "publish-$NETWORK.json"; then
  echo "Publish failed:"; cat "publish-$NETWORK.json"; exit 1
fi

python3 - "$NETWORK" <<'PY'
import json, sys
network = sys.argv[1]
out = json.load(open(f"publish-{network}.json"))
package = next(c["packageId"] for c in out["objectChanges"] if c["type"] == "published")
registry = next(c["objectId"] for c in out["objectChanges"]
                if c["type"] == "created" and c["objectType"].endswith("::counter::Registry"))
print(f"\nDone on {network}.")
print("Package ID: ", package)
print("Registry ID:", registry)
print("Digest:     ", out["digest"])
print("\nSend this output to Claude so it can update deployments.json and DEPLOYS.md.")
PY
