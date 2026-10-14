# Web3 in Flutter

One Flutter app, **Flutter Counter**, that proves Flutter can be a complete Web3 client. It does three things on every major chain family:

1. **Reads** blockchain data: balances, recent activity and counter values.
2. **Authenticates** users in three ways:
   - the app is the wallet;
   - it connects to wallets already installed on the device, without an SDK;
   - it connects through an SDK (Reown AppKit, and near_wallet_connect for NEAR).

   Users then sign in to a backend with a signed message.

3. **Writes** to the blockchain by calling a counter contract.

| Chain family | Networks                                            |
| ------------ | --------------------------------------------------- |
| EVM          | Sepolia, Base Sepolia, Arbitrum Sepolia, OP Sepolia |
| Solana       | devnet                                              |
| Sui          | testnet                                             |
| Cosmos       | Osmosis testnet (`osmo-test-5`)                     |
| NEAR         | testnet                                             |

> **Testnets only.** The keys in `keys/` are public on purpose so that anyone can redeploy and test. Never send real funds to them.

## How Wallets Connect

Whichever way a wallet connects, the rest of the app sees the same signer: an address that signs messages (for sign-in) and transactions (for writes).

|                                               | Android                                                        | iOS                                     | Web                                                                     | macOS, Windows, Linux |
| --------------------------------------------- | -------------------------------------------------------------- | --------------------------------------- | ----------------------------------------------------------------------- | --------------------- |
| 1. In-app wallet                              | every chain                                                    | every chain                             | every chain                                                             | every chain           |
| 2. Installed wallet, no SDK                   | Solana: Mobile Wallet Adapter, Phantom and Solflare deep links | Solana: Phantom and Solflare deep links | EVM (EIP-6963), Solana and Sui (Wallet Standard), Osmosis (Keplr, Leap) | none                  |
| 2. Open the web version in a wallet's browser | MetaMask, Phantom, Solflare, Keplr                             | same                                    | (not needed)                                                            | none                  |
| 3. SDK                                        | EVM and Solana (Reown AppKit), NEAR (Intear)                   | same                                    | NEAR (Intear)                                                           | NEAR (Intear)         |

Gaps are real limits, not missing work: EVM, Sui and Cosmos wallet apps can only be reached from a native app through WalletConnect, and NEAR wallets have no SDK-free way in. The Sign in screen explains each one where it applies.

Reown needs a project ID. The one in `flutter/lib/src/wallet/sdk/sdk_wallets.dart` is public and only accepts this app's IDs (`com.keepdeploying.flutter_counter`, `com.keepdeploying.flutterCounter`). For your own app, create a project at [dashboard.reown.com](https://dashboard.reown.com) and allowlist your app's IDs there.

## Repo Layout

| Folder       | What it holds                                                                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `flutter/`   | The Flutter app                                                                                                                  |
| `server/`    | Pure Dart backend: nonces, signature verifiers for every chain, sessions                                                         |
| `contracts/` | The counter contract for each chain, and `deployments.json` with every address                                                   |
| `keys/`      | Public testnet keys: the dev recovery phrase and the Android debug keystore                                                      |
| `scripts/`   | Publish the web app to GitHub Pages and the APK to GitHub Releases                                                               |
| `tool/`      | `setup_platforms.dart`, `sync_deployments.dart`, and `verify_signatures/` (checks our signatures with each chain's JS libraries) |
| `DEPLOYS.md` | Log of every contract deploy, web deploy and APK release                                                                         |

The repo commits only source code and the files that declare dependencies. Platform folders (`flutter/android/`, `flutter/ios/`, and so on), build output and downloaded dependencies are generated on your machine.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or newer (Dart 3.13 or newer)
- For each platform you want to run, its usual Flutter setup (Android Studio, Xcode, Visual Studio, or the Linux desktop packages)
- On Linux: `libsecret-1-dev` to build, and a running keyring (GNOME Keyring or KWallet) to save the in-app wallet. Without a keyring, the wallet stays in memory until the app closes.

You only need the chain toolchains (Foundry, Anchor, Sui CLI, and so on) if you want to redeploy contracts. See `contracts/README.md`.

## Run the App

```bash
git clone https://github.com/keepdeploying/web3-in-flutter.git
cd web3-in-flutter
flutter pub get
dart run tool/setup_platforms.dart
cd flutter
flutter run
```

`tool/setup_platforms.dart` runs `flutter create` for Android, iOS, web, macOS, Windows and Linux. It then applies the changes this app needs:

- the Android INTERNET permission, macOS network access and the shared signing key;
- what `local_auth` needs for fingerprint and Face ID unlock (a `FlutterFragmentActivity`, the `USE_BIOMETRIC` permission, an AppCompat launch theme and `NSFaceIDUsageDescription`);
- what wallets need: the `fluttercounter://` link they answer on, the wallet apps the app may look for (Android `<queries>`, iOS `LSApplicationQueriesSchemes`), plain WebSockets to `localhost` for the Mobile Wallet Adapter, and Flutter's own deep linking turned off;
- a Gradle fix for a plugin Reown AppKit brings in (`coinbase_wallet_sdk` compiles against an old Android API and names a file it doesn't ship).

It is safe to run again, and worth re-running after pulling changes to it.

## Run From Your IDE

- **VS Code:** open the repository's root folder and accept the recommended extensions. The Run and Debug view (Ctrl/Cmd + Shift + D) then lists the app (debug, profile, release, Chrome), the tests, the server, and "Server and Flutter" together. Opening the `flutter` folder on its own works too.
- **Android Studio:** open the repository's root folder. The run configurations in `.idea/runConfigurations` show up in the toolbar.

## Run the Server

```bash
cd server
dart run bin/server.dart
```

The server listens on `http://localhost:8080`. By default, the app runs the same Dart code in-process, so you only need the server if you want to test the HTTP backend.

## Tests

```bash
cd flutter && flutter test
cd server && dart test
```

## Try It From the Command Line

The app's chain code is plain Dart, so these tools run it against the real testnets with the dev recovery phrase in `keys/`:

```bash
cd flutter
dart run tool/addresses.dart      # the dev wallet's address on every chain
dart run tool/live_reads.dart     # read every counter, through the RPC pools
dart run tool/try_writes.dart     # send increment, decrement and reset on every network
dart run tool/try_sign_in.dart    # sign in to a running server on every network and level
dart run tool/sign_vectors.dart   # signatures to check with tool/verify_signatures
```

`try_writes.dart` sends real transactions and spends a little test currency. Pass network IDs (`sepolia`, `solana-devnet`, `sui-testnet`...) to run only some.

## Toolchain Versions Used

| Tool                                 | Version                                                                   |
| ------------------------------------ | ------------------------------------------------------------------------- |
| Flutter / Dart                       | 3.47.6 / 3.13.5                                                           |
| Foundry / Solidity                   | 1.8.4 / 0.8.37                                                            |
| Anchor / Agave (Solana CLI)          | 1.2.0 / 4.3.0                                                             |
| Sui CLI                              | 1.81.0                                                                    |
| osmosisd                             | 31.0.3                                                                    |
| near-cli-rs / cargo-near             | 0.30.1 / 0.22.0                                                           |
| Rust                                 | 1.97 (host), 1.86 for CosmWasm, Solana platform tools for on-chain builds |
| binaryen (wasm-opt) / cosmwasm-check | 133 / 2.2.10                                                              |

## Publish

Nothing publishes automatically. Run these by hand and record each run in `DEPLOYS.md`:

```bash
scripts/deploy-pages.sh   # builds the web app and pushes it to the gh-pages branch
scripts/release-apk.sh    # builds the APK and creates a GitHub Release (needs the gh CLI)
```
