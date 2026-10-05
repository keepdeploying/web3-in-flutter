#!/usr/bin/env bash
# Installs the chain toolchains the deploy scripts need, skipping anything
# already installed. Works on macOS (Homebrew needed for binaryen) and Linux.
#
#   ./install-tools.sh
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
step() { echo; echo "=== $1"; }

step "Rust"
have rustup || curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# shellcheck disable=SC1091
source "$HOME/.cargo/env"
rustup target add wasm32-unknown-unknown

step "Foundry (EVM)"
if ! have forge; then
  curl -L https://foundry.paradigm.xyz | bash
  "$HOME/.foundry/bin/foundryup"
fi

step "Solana CLI and Anchor"
if ! have solana || ! have anchor; then
  curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash
fi
have avm && avm install 1.2.0 && avm use 1.2.0 || true

step "Sui CLI"
if ! have sui; then
  curl -sSfL https://raw.githubusercontent.com/Mystenlabs/suiup/main/install.sh | sh
  "$HOME/.local/bin/suiup" install sui@testnet -y || echo "Run: suiup install sui@testnet"
fi

step "Osmosis CLI and wasm-opt (CosmWasm)"
if ! have osmosisd; then
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH=amd64; [ "$ARCH" = "aarch64" ] && ARCH=arm64
  mkdir -p "$HOME/.local/bin"
  curl -fsSL -o "$HOME/.local/bin/osmosisd" \
    "https://github.com/osmosis-labs/osmosis/releases/download/v31.0.3/osmosisd-31.0.3-$OS-$ARCH"
  chmod +x "$HOME/.local/bin/osmosisd"
fi
if ! have wasm-opt; then
  if have brew; then brew install binaryen; else echo "Install binaryen (wasm-opt) with your package manager."; fi
fi
have cosmwasm-check || cargo install cosmwasm-check --version "~2.2" --locked

step "NEAR CLI and cargo-near"
have near || curl --proto '=https' --tlsv1.2 -LsSf https://github.com/near/near-cli-rs/releases/latest/download/near-cli-rs-installer.sh | sh
have cargo-near || curl --proto '=https' --tlsv1.2 -LsSf https://github.com/near/cargo-near/releases/latest/download/cargo-near-installer.sh | sh

echo
echo "Done. Open a new terminal so PATH changes apply, then check versions with:"
echo "  forge --version; anchor --version; solana --version; sui --version; osmosisd version; near --version; cargo near --version"
