/// Backend logic for Flutter Counter.
///
/// Everything in `lib/` is pure Dart and never imports `dart:io`, so the
/// Flutter app can also run it in-process (the `LocalBackend`), including on
/// the web. Only `bin/server.dart` wraps it in an HTTP server.
///
/// The app also uses the shared pieces directly: [ChainFamily], the message
/// formats each chain signs, and [SignedMessage].
library;

export 'src/chain_family.dart';
export 'src/health.dart';
export 'src/signing/message_formats.dart';
export 'src/signing/signed_message.dart';
