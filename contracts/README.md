# Contracts

Every chain gets the same simple **counter**:

- Each user has their own counter, which can be incremented, decremented or reset.
- The contract also tracks the total number of users.

| Folder | Chain | Language and tooling |
| --- | --- | --- |
| `evm/` | Sepolia, Base Sepolia, Polygon Amoy, Arbitrum Sepolia | Solidity, Foundry |
| `solana/` | Solana devnet | Rust, Anchor |
| `sui/` | Sui testnet | Move, Sui CLI |
| `cosmwasm/` | Osmosis testnet | Rust, CosmWasm |
| `near/` | NEAR testnet | Rust, near-sdk, cargo-near |

Each folder's README explains how to install the tooling, then build, test and deploy. To install every toolchain at once, run:

```bash
./install-tools.sh
```

## Deploy Everything

Every deploy script needs the network named explicitly, so nothing goes to a real network by accident:

```bash
./evm/deploy.sh all            # Sepolia, Base Sepolia, Polygon Amoy, Arbitrum Sepolia
./solana/deploy.sh devnet
./sui/deploy.sh testnet
./cosmwasm/deploy.sh osmo-test-5
./near/deploy.sh testnet
```

Each script runs the tests first, then deploys with the public dev wallet and prints the address or ID. Deployed addresses go in `deployments.json`, which the app reads, and in `../DEPLOYS.md`.

The deployer on every chain is the dev account from `../keys/dev-mnemonic.txt`.
