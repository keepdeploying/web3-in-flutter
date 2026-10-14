/// Backend logic for Flutter Counter.
///
/// Everything in `lib/` is pure Dart and never imports `dart:io`, so the
/// Flutter app can also run it in-process (the `LocalBackend`), including on
/// the web. Only `bin/server.dart` wraps it in an HTTP server.
///
/// The app also uses the shared pieces directly: [ChainFamily], the message
/// formats each chain signs, and [SignedMessage].
library;

export 'src/auth/chain_lookup.dart';
export 'src/auth/counter_server.dart';
export 'src/auth/description_store.dart';
export 'src/auth/nonce_store.dart';
export 'src/auth/session_tokens.dart';
export 'src/auth/sign_in_messages.dart';
export 'src/auth/signature_verifier.dart';
export 'src/chain_family.dart';
export 'src/health.dart';
export 'src/signing/message_formats.dart';
export 'src/signing/signed_message.dart';
