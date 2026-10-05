#!/usr/bin/env bash
# Builds, tests and deploys the Flutter Counter Anchor program to Solana
# devnet, then uploads its IDL. Pays with the public dev wallet in keys/.
#
#   ./deploy.sh devnet
#   ./deploy.sh localnet   # a local solana-test-validator
#
# The network is always explicit, so nothing deploys by accident.
set -euo pipefail
cd "$(dirname "$0")"

for tool in solana anchor cargo; do
  command -v $tool >/dev/null || {
    echo "$tool is missing. Install the Solana toolchain (Rust, Solana CLI, Anchor) with:"
    echo "  curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash"
    echo "Then make sure 'anchor --version' prints 1.2.0 (avm install 1.2.0 && avm use 1.2.0)."
    exit 1
  }
done

case "${1:-}" in devnet|localnet) ;; *) echo "Usage: ./deploy.sh devnet|localnet"; exit 1 ;; esac
CLUSTER=$1
# The Solana CLI calls the local validator "localhost"; Anchor calls it "localnet".
URL=$([ "$CLUSTER" = localnet ] && echo localhost || echo "$CLUSTER")
KEYS=../../keys
# Anchor looks for the program keypair here. target/ is gitignored, so copy it
# from keys/ to keep the program ID stable on every machine.
mkdir -p target/deploy
cp "$KEYS/solana-program-keypair.json" target/deploy/flutter_counter-keypair.json

anchor build
cargo test

echo "Deploying from $(solana-keygen pubkey $KEYS/solana-dev-keypair.json) to $CLUSTER"
solana balance "$(solana-keygen pubkey $KEYS/solana-dev-keypair.json)" --url "$URL"
anchor program deploy --provider.cluster "$CLUSTER" --program-name flutter_counter

echo
echo "Done. Program ID: $(solana-keygen pubkey target/deploy/flutter_counter-keypair.json)"
echo "Send this output to Claude so it can update deployments.json and DEPLOYS.md."
