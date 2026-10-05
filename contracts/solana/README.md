# Counter on Solana

An [Anchor](https://www.anchor-lang.com) 1.2 program, `flutter_counter`, deployed on devnet at `B5FWXqM3hrna9SCPp2r2APzEmaMzash3N6t9kkwpD5qH`.

| Account | Seeds | Holds |
| --- | --- | --- |
| `Global` | `["global"]` | `total_users` |
| `Counter` | `["counter", user]` | `user`, `value` (`i64`), `bump` |

| Instruction | What it does |
| --- | --- |
| `increment`, `decrement`, `reset` | Change the signer's counter |

All three take the same accounts: `global`, `counter`, `user` (signer, pays rent) and `system_program`.

- **No separate setup instruction.** Both accounts use `init_if_needed`: the first call creates them, and the user pays their rent.
- **Events:** `UserRegistered` and `CounterChanged`.
- **IDL:** the program's interface is in `target/idl/flutter_counter.json` after a build. Deploying also uploads it on-chain.

## Install

The official one-line installer sets up Rust, the Solana CLI and Anchor (through AVM):

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://solana-install.solana.workers.dev | bash
avm install 1.2.0 && avm use 1.2.0
```

`rust-toolchain.toml` pins the Rust version used for the host-side tests. The on-chain build uses the Rust that ships with the Solana platform tools.

## Build and Test

```bash
anchor build    # builds target/deploy/flutter_counter.so and the IDL
cargo test      # runs the program in LiteSVM, an in-process Solana runtime
```

## Deploy

```bash
./deploy.sh devnet
```

- **Fees:** paid by the public dev wallet, `../../keys/solana-dev-keypair.json`.
- **Program ID:** comes from `../../keys/solana-program-keypair.json`, so it stays the same on every machine.
- **Upgrades:** deploying again upgrades the same program.

To try it on a local validator first:

```bash
solana-test-validator --reset   # in another terminal
solana airdrop 20 DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX --url localhost
./deploy.sh localnet
```
