# Counter on CosmWasm (Osmosis Testnet)

A CosmWasm contract that keeps an `i64` counter per sender, plus the number of users.

| Message                                                        | What it does                     |
| -------------------------------------------------------------- | -------------------------------- |
| Execute `{"increment":{}}`, `{"decrement":{}}`, `{"reset":{}}` | Change the sender's counter      |
| Query `{"value":{"user":"osmo1..."}}`                          | `{"value": 0, "is_user": false}` |
| Query `{"total_users":{}}`                                     | `{"total_users": 0}`             |

Events: `wasm-user_registered` and `wasm-counter_changed`.

## Why the Versions Are Pinned

Osmosis v31 runs wasmvm 2.2:

- **`cosmwasm-std = "2.2"`** to match that VM.
- **Rust 1.86** (`rust-toolchain.toml`).
- **`target-cpu=mvp`** (`.cargo/config.toml`), so the build sticks to plain "MVP" WebAssembly.
- **`wasm-opt --signext-lowering`** to clean up the rest.

`cosmwasm-check` (version 2.2) confirms the result is valid for that VM.

## Install

```bash
# Rust (rust-toolchain.toml installs 1.86 and the wasm32 target automatically)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# wasm-opt
brew install binaryen
# osmosisd, the Osmosis CLI (Apple Silicon build shown)
curl -L -o /usr/local/bin/osmosisd \
  https://github.com/osmosis-labs/osmosis/releases/download/v31.0.3/osmosisd-31.0.3-darwin-arm64
chmod +x /usr/local/bin/osmosisd
# optional: checks the wasm the same way the chain does
cargo install cosmwasm-check --version "~2.2" --locked
```

## Build and Test

```bash
cargo test
cargo wasm
wasm-opt -Os --signext-lowering target/wasm32-unknown-unknown/release/flutter_counter.wasm \
  -o artifacts/flutter_counter.wasm
cosmwasm-check artifacts/flutter_counter.wasm
```

## Deploy

```bash
./deploy.sh osmo-test-5
```

The script builds and checks the wasm, then imports the public dev wallet into a separate keyring in `.osmosis-home/`. `osmosisd` builds and signs each transaction offline, and Python broadcasts it through the chain's REST API. Some networks block `osmosisd`'s own RPC requests (the cloud machine that ran the first deploy did). The script stores the code, instantiates the contract with no admin, and prints the code ID and the contract address.
