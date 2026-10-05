# Counter on NEAR

A [near-sdk](https://github.com/near/near-sdk-rs) 5.29 contract. Each account's counter (`i64`) lives in a `LookupMap`, alongside `total_users`. It's deployed on `flutter-counter.testnet`.

| Method | Kind | What it does |
| --- | --- | --- |
| `increment()`, `decrement()`, `reset()` | change | Change the caller's counter and return the new value |
| `get_value({"account_id": "..."})` | view | A counter (0 if the account never called) |
| `is_user({"account_id": "..."})`, `total_users()` | view | Reads |

Events follow [NEP-297](https://nomicon.io/Standards/EventsFormat), with standard `flutter_counter` and events `user_registered` and `counter_changed`. They appear in transaction logs as `EVENT_JSON:{...}`.

There is no init method. The contract starts with empty state (`Default`).

## Install

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/near/near-cli-rs/releases/latest/download/near-cli-rs-installer.sh | sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/near/cargo-near/releases/latest/download/cargo-near-installer.sh | sh
```

## Build and Test

```bash
cargo test
cargo near build non-reproducible-wasm   # writes target/near/flutter_counter.wasm
```

The build uses Wasm bulk-memory instructions, which NEAR has accepted since nearcore 2.12.

## Deploy

```bash
./deploy.sh testnet
```

The script deploys to `flutter-counter.testnet`, signing with the public dev recovery phrase (`m/44'/397'/0'`). That account was created through the testnet faucet helper, with the dev key as its full-access key.
