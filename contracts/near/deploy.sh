#!/usr/bin/env bash
# Builds the Flutter Counter NEAR contract and deploys it to the
# flutter-counter.testnet account, signing with the public dev recovery
# phrase. The network is always explicit:
#
#   ./deploy.sh testnet
set -euo pipefail
cd "$(dirname "$0")"

[ "${1:-}" = "testnet" ] || { echo "Usage: ./deploy.sh testnet"; exit 1; }
ACCOUNT=flutter-counter.testnet

for tool in cargo cargo-near near; do
  command -v $tool >/dev/null || { echo "$tool is missing. See README.md for install steps."; exit 1; }
done

echo "1. Testing and building the contract..."
cargo test
cargo near build non-reproducible-wasm

echo "2. Deploying to $ACCOUNT on testnet..."
# The contract has no init method: its state starts empty (Default).
near contract deploy "$ACCOUNT" \
  use-file target/near/flutter_counter.wasm \
  without-init-call \
  network-config testnet \
  sign-with-seed-phrase "$(cat ../../keys/dev-mnemonic.txt)" \
    --seed-phrase-hd-path "m/44'/397'/0'" \
  send

echo
echo "Done. Contract: $ACCOUNT"
echo "Send this output to Claude so it can update deployments.json and DEPLOYS.md."
