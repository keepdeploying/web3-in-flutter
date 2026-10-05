# Public Testnet Keys

> These keys are public on purpose, so anyone can redeploy the contracts and run the end-to-end tests. Use them on testnets only. Never send real funds to them.

| File | What it is |
| --- | --- |
| `dev-mnemonic.txt` | The dev recovery phrase. It derives the deployer and test account on every chain. |
| `solana-dev-keypair.json` | The dev wallet's Solana key as a Solana CLI keypair file. Regenerate it with `cd flutter && dart run tool/solana_keypair.dart`. |
| `solana-program-keypair.json` | The Solana program's keypair. It fixes the program ID to `B5FWXqM3hrna9SCPp2r2APzEmaMzash3N6t9kkwpD5qH`. |
| `android-debug.keystore` | Signs every Android build, so an APK built on any machine installs over an earlier one. Password `android`, alias `androiddebugkey`. |

Print the dev addresses with:

```bash
cd flutter
dart run tool/addresses.dart
```

| Chain | Path | Address |
| --- | --- | --- |
| EVM (all four networks) | `m/44'/60'/0'/0/0` | `0xfFFAa29e82d5455985a908235536d2cD01aCce47` |
| Solana | `m/44'/501'/0'/0'` | `DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX` |
| Sui | `m/44'/784'/0'/0'/0'` | `0x78c51a7b5ae65f0966b1cad833ee3ef6ededbe9bc6ff4579543c70ff9c67d29e` |
| Osmosis | `m/44'/118'/0'/0/0` | `osmo1ed3nqhzlm58pzehnajalx4q5wt4zs85p2cud7a` |
| NEAR (implicit account) | `m/44'/397'/0'` | `92b28ade98c901eaeb5cd6de863d7b5e9684ca2718c7efd556af051cc4ac5670` |

These are the same paths MetaMask, Phantom, Slush, Keplr and NEAR wallets use. Importing the phrase into those wallets shows the same addresses.
