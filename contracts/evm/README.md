# Counter on EVM

`src/FlutterCounter.sol` keeps an `int256` counter per address, plus `totalUsers`. A user is registered on their first call.

| Function | What it does |
| --- | --- |
| `increment()`, `decrement()`, `reset()` | Change the caller's counter |
| `counterOf(address)` | Read anyone's counter |
| `totalUsers()` | How many addresses have used the counter |
| `isUser(address)` | Whether an address has used it |

Events: `UserRegistered(user, totalUsers)` and `CounterChanged(user, oldValue, newValue, action)`.

## Same Address on Every Network

`script/Deploy.s.sol` deploys with CREATE2 through the standard deterministic deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`). That deployer exists on Sepolia, Base Sepolia, Polygon Amoy and Arbitrum Sepolia.

The address depends only on the deployer, the salt and the exact bytecode. `foundry.toml` pins the compiler and turns off metadata hashes, so every machine builds the same bytecode. The result is the same address everywhere: `0x49f5A4DD302f5BA6F3414c7827428dbBe8E8D16d`.

## Install

1. Install [Foundry](https://getfoundry.sh):

   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

2. Install the dependencies. forge-std comes from [Soldeer](https://soldeer.xyz), Foundry's package manager, not a git submodule. It's declared in `foundry.toml` and downloads into the gitignored `dependencies/` folder.

   ```bash
   forge soldeer install
   ```

## Build and Test

```bash
forge build
forge test
```

## Deploy

```bash
./deploy.sh all                     # Sepolia, Base Sepolia, Polygon Amoy, Arbitrum Sepolia
./deploy.sh sepolia                 # just one network
```

The script signs with the public dev wallet in `../../keys/dev-mnemonic.txt` and verifies the source on Sourcify. If the counter is already deployed on a network, it skips that network.

To try it locally first, run `anvil` in another terminal, then:

```bash
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```
