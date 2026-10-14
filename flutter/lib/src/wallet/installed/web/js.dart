import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../installed_wallet.dart';

/// Makes a plain JavaScript object from [fields].
JSObject jsObject(Map<String, JSAny?> fields) {
  final object = JSObject();
  fields.forEach((key, value) => object.setProperty(key.toJS, value));
  return object;
}

/// Awaits a wallet's promise and turns a rejection into a
/// [WalletException] with the wallet's code and message.
Future<T> walletCall<T extends JSAny?>(String wallet, JSPromise<T> Function() call) async {
  try {
    return await call().toDart;
  } catch (error) {
    throw walletError(wallet, error);
  }
}

/// Reads `code` and `message` from whatever the wallet threw.
WalletException walletError(String wallet, Object error) {
  if (error is WalletException) return error;
  Object? code;
  String? message;
  try {
    final object = error as JSObject;
    code = object.getProperty<JSAny?>('code'.toJS).dartify();
    message = object.getProperty<JSAny?>('message'.toJS).dartify() as String?;
  } catch (_) {
    // Not a JavaScript object: fall back to its text.
  }
  message ??= '$error';
  // 4001 is EIP-1193's "user rejected". Other wallets only say it in words.
  final declined = code == 4001 || RegExp('reject|denied|declin|cancel', caseSensitive: false).hasMatch(message);
  return WalletException(
    declined ? 'You declined the request in $wallet.' : '$wallet: $message',
    code: code,
    declined: declined,
  );
}
