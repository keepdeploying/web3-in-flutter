# Flutter Counter Server

The backend for Flutter Counter, in pure Dart.

- `lib/`: the logic (nonces, a signature verifier for each chain, sessions, a description store). It never imports `dart:io`, so the Flutter app can also run it in-process, including on the web. In the app, that's the `LocalBackend`.
- `bin/server.dart`: wraps `lib/` in a [shelf](https://pub.dev/packages/shelf) HTTP server. In the app, that's the `HttpBackend`.

## Run

```bash
dart run bin/server.dart          # listens on http://localhost:8080
PORT=9090 dart run bin/server.dart
```

Check it with `curl http://localhost:8080/health`.

## Test

```bash
dart test
```

## Deploy It Yourself

This repo doesn't host the server. Any host that runs a Dart executable or a Docker container works:

1. Run `dart compile exe bin/server.dart -o server`.
2. Run the binary with a `PORT` environment variable.
3. Set the server's URL in the app's backend settings.
