# Flutter Counter Server

The backend for Flutter Counter, in pure Dart.

- `lib/`: the logic (nonces, a signature verifier for each chain, sessions, a description store). It never imports `dart:io`, so the Flutter app can also run it in-process, including on the web. In the app, that's the `LocalBackend`.
- `bin/server.dart`: wraps `lib/` in a [shelf](https://pub.dev/packages/shelf) HTTP server. In the app, that's the `HttpBackend`.

## Run

```bash
dart run bin/server.dart          # listens on http://localhost:8080
PORT=9090 dart run bin/server.dart
```

Check it with `curl http://localhost:8080/health`. Then sign in to it with the dev recovery phrase on every network and level:

```bash
cd ../flutter && dart run tool/try_sign_in.dart
```

Settings, all optional, as environment variables:

| Variable                | Default               | What it does                                                                    |
| ----------------------- | --------------------- | ------------------------------------------------------------------------------- |
| `PORT`                  | `8080`                | The port to listen on.                                                          |
| `SESSION_SECRET`        | random at start       | Hex key that signs session tokens. Set it, or every restart signs everyone out. |
| `APP_DOMAIN`, `APP_URI` | `flutter-counter.app` | What level 3 messages must name. Use your web app's real domain.                |

## API

| Route                  | Body                                | Answer                                         |
| ---------------------- | ----------------------------------- | ---------------------------------------------- |
| `GET /health`          |                                     | `{ok, service, mode}`                          |
| `POST /auth/challenge` | `{level, family, address, chainId}` | the message to sign, with its nonce            |
| `POST /auth/sign-in`   | `{signed, level, chainId}`          | every check, and a session token if all passed |
| `GET /me`              | `Authorization: Bearer <token>`     | the session                                    |
| `PUT /me/description`  | `{text}`, with the token            | the saved description                          |
| `GET /descriptions`    |                                     | every description, newest first                |

## Sign-in levels

| Level | Message                                                                                                                                                   | What it stops                                                |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| 1     | the same text every time                                                                                                                                  | nothing: a copied signature works forever                    |
| 2     | the text and a one-time nonce                                                                                                                             | replays, but not phishing: the message doesn't name the site |
| 3     | domain, address, URI, chain ID, nonce, issue and expiry times (Sign-In with Ethereum layout, used for every chain; NEP-413's nonce and recipient on NEAR) | replays and phishing                                         |

The signature itself is checked per chain in `lib/src/auth/signature_verifier.dart`. Some cases need the chain: smart contract wallets on EVM (ERC-1271), named NEAR accounts (is the key a full-access key?) and Sui zkLogin. `RpcChainLookup` asks public testnet endpoints for those.

## Test

```bash
dart test                         # offline
dart test -t live --run-skipped   # also asks the testnets (Sui, NEAR, EVM)
```

`test/fixtures/in_app_signatures.json` holds signatures from the app's in-app wallet that each chain's own JavaScript library verified (`tool/verify_signatures`).

## Deploy It Yourself

This repo doesn't host the server. Any host that runs a Dart executable or a Docker container works:

1. Run `dart compile exe bin/server.dart -o server`.
2. Run the binary with `PORT`, `SESSION_SECRET` and `APP_DOMAIN` set.
3. Set the server's URL in the app's backend settings.
