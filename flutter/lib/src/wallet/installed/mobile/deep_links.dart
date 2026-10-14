import 'dart:async';

import 'package:app_links/app_links.dart';

/// The links wallet apps open to answer the app: `fluttercounter://wallet/...`.
///
/// The app asks a wallet something by opening the wallet's link with a
/// `redirect_link` of ours. The wallet shows the request, then opens our
/// link with the answer in its query. Android and iOS hand that link to
/// the app (see the intent filter and URL scheme that
/// `tool/setup_platforms.dart` adds), and app_links passes it here.
class DeepLinks {
  DeepLinks._() {
    AppLinks().uriLinkStream.listen(_received);
  }

  static final instance = DeepLinks._();

  static const scheme = 'fluttercounter';
  static const host = 'wallet';

  final _waiting = <String, Completer<Uri>>{};
  final _forwards = <String, void Function(Uri uri)>{};

  /// Sends every link with [path] to [handler], for an SDK that reads the
  /// answers itself (Reown AppKit).
  void forward(String path, void Function(Uri uri) handler) => _forwards[path] = handler;

  /// The link a wallet should open to answer: `fluttercounter://wallet/<path>`.
  Uri redirectFor(String path) => Uri(scheme: scheme, host: host, path: '/$path');

  /// Waits for the wallet to open the link made by [redirectFor] with [path].
  /// Gives up after [timeout], for when the user never comes back.
  Future<Uri> waitFor(String path, {Duration timeout = const Duration(minutes: 5)}) {
    _waiting[path]?.completeError(StateError('Replaced by a newer request'));
    final completer = _waiting[path] = Completer<Uri>();
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(path);
        throw TimeoutException('The wallet did not answer.');
      },
    );
  }

  void _received(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return;
    final path = uri.path.replaceFirst('/', '');
    _forwards[path]?.call(uri);
    _waiting.remove(path)?.complete(uri);
  }
}
