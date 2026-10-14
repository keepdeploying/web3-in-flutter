# Flutter Counter App

The Flutter client. See the root README for how to set up the platform folders and run it.

## Useful Commands

```bash
flutter run -d chrome          # web
flutter run -d linux           # or macos, windows
flutter test
dart run tool/addresses.dart   # print the dev wallet's address on every chain
```

## Where Things Are

| Folder (in `lib/src/`) | What it does                                                                                                                                                                                                                                                               |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `chains/`              | Networks, and per chain family a reader (balances, activity, the counter) and a writer (builds, signs and sends counter transactions with no chain SDK)                                                                                                                    |
| `rpc/`                 | `RpcPool`: free public endpoints per network, tried in order, with cooldowns for the ones that fail                                                                                                                                                                        |
| `wallet/`              | The `WalletSigner` interface. The in-app wallet: `hd_keys.dart` (key derivation), `vault*.dart` (where the phrase is kept on each platform), `in_app_signer.dart`                                                                                                          |
| `wallet/installed/`    | Installed wallets with no SDK. `web/`: EIP-6963, Wallet Standard and Keplr through `dart:js_interop`. `mobile/`: Phantom and Solflare deep links (with `nacl_box.dart`), the Mobile Wallet Adapter (`mwa.dart`), and links that open the web version in a wallet's browser |
| `wallet/sdk/`          | Wallets through SDKs: Reown AppKit (Android and iOS) and near_wallet_connect                                                                                                                                                                                               |
| `backend/`             | The sign-in backend, either inside the app or over HTTP (the server in `server/`)                                                                                                                                                                                          |
| `state/`               | `AppState` and its controllers: the in-app wallet, connected wallets, the sign-in session                                                                                                                                                                                  |
| `screens/`, `ui/`      | The four screens, the layout for every window size, and shared widgets                                                                                                                                                                                                     |

Every screen has a "What's happening" panel that shows each step the app takes, with the data it sends and receives.
