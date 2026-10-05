# Counter on Sui

A Move package with one module, `flutter_counter::counter`. Publishing it creates one shared `Registry` object, which holds:

- every user's counter, in a `Table<address, Value>`;
- `total_users`.

**Move has no signed integers**, so a counter is stored as a `Value { negative: bool, magnitude: u64 }`. Zero is never negative.

| Function | What it does |
| --- | --- |
| `increment(registry)`, `decrement(registry)`, `reset(registry)` | Change the sender's counter |
| `value_of(registry, user)` | Returns `(negative, magnitude)` |
| `total_users(registry)`, `is_user(registry, user)` | Reads |

Events: `UserRegistered` and `CounterChanged`.

## Install

Install the Sui CLI with [suiup](https://github.com/MystenLabs/suiup):

```bash
curl -sSfL https://raw.githubusercontent.com/Mystenlabs/suiup/main/install.sh | sh
suiup install sui@testnet
```

Or use `brew install sui`.

## Test

```bash
sui move test
```

## Deploy

```bash
./deploy.sh testnet
./deploy.sh local     # after `sui start --with-faucet --force-regenesis` in another terminal
```

- **Network is required.** The script never assumes one.
- **Its own config:** it keeps a separate Sui CLI config in `.sui-config/`, so it doesn't touch your own `~/.sui` wallet.
- **Wallet:** it imports the public dev wallet and publishes from it.
- **Output:** it prints the package ID and the `Registry` object ID. The app needs both.
