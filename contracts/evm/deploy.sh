#!/usr/bin/env bash
# Deploys FlutterCounter to the EVM testnets with CREATE2, so it gets the same
# address on every network. Signs with the public dev wallet in keys/.
#
#   ./deploy.sh all                  # all four networks
#   ./deploy.sh sepolia base_sepolia # only these
#
# The networks are always explicit, so nothing deploys by accident.
#
# Network names come from [rpc_endpoints] in foundry.toml.
set -euo pipefail
cd "$(dirname "$0")"

command -v forge >/dev/null || {
  echo "Foundry is missing. Install it with:"
  echo "  curl -L https://foundry.paradigm.xyz | bash && foundryup"
  exit 1
}

MNEMONIC=../../keys/dev-mnemonic.txt
SENDER=0xfFFAa29e82d5455985a908235536d2cD01aCce47
ALL=(sepolia base_sepolia arbitrum_sepolia optimism_sepolia)
[ $# -gt 0 ] || { echo "Usage: ./deploy.sh all | <network>... (${ALL[*]})"; exit 1; }
if [ "$1" = all ]; then NETWORKS=("${ALL[@]}"); else NETWORKS=("$@"); fi

forge soldeer install
forge test

for NET in "${NETWORKS[@]}"; do
  echo
  echo "=== $NET"
  forge script script/Deploy.s.sol:Deploy \
    --rpc-url "$NET" \
    --broadcast \
    --mnemonics "$MNEMONIC" --mnemonic-indexes 0 --sender "$SENDER"

  # Publish the source on Sourcify (no API key needed). Not fatal if it fails.
  ADDRESS=$(forge script script/Deploy.s.sol:Deploy --rpc-url "$NET" 2>/dev/null \
    | grep -oE 'Predicted address: 0x[0-9a-fA-F]{40}' | grep -oE '0x[0-9a-fA-F]{40}')
  CHAIN_ID=$(cast chain-id --rpc-url "$NET")
  forge verify-contract "$ADDRESS" src/FlutterCounter.sol:FlutterCounter \
    --chain "$CHAIN_ID" --verifier sourcify || echo "Sourcify verification failed on $NET (not fatal)."
done

echo
echo "Done. FlutterCounter is at $ADDRESS on every network above."
echo "Send this whole output to Claude so it can update deployments.json and DEPLOYS.md."
