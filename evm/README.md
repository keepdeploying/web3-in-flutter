## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Faucets

https://cloud.google.com/application/web3/faucet/ethereum/sepolia


## Deployments

#### Sepolia
Deployment Transaction
https://sepolia.etherscan.io/tx/0x3e67bffc08f5cfa27f8c270ca1c10dd1e64ba04411eb1b85e99aa72fc01d885c

Contract on Explorer
https://sepolia.etherscan.io/address/0x00E5ebC4b76082505F51bd8559c4EB0048f7E90e

Contract Address
0x00E5ebC4b76082505F51bd8559c4EB0048f7E90e

## Usage

### Build

```shell
$ forge build
```

### Deploy

```shell
cast wallet import flutter-deployer --interactive

forge create ./src/FlutterCounter.sol:FlutterCounter --rpc-url https://sepolia.drpc.org --account flutter-deployer
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
