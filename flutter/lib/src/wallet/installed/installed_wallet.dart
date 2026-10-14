import 'package:flutter/foundation.dart';

import '../../chains/networks.dart';
import '../wallet_signer.dart';
import 'finder_native.dart' if (dart.library.js_interop) 'finder_web.dart' as platform;

/// A wallet the app found on this device: a browser extension on the web,
/// a wallet app on a phone. The app talks to it directly, with no SDK.
abstract class InstalledWallet {
  /// Stable for one wallet, like `io.metamask` or `Phantom`.
  String get id;

  /// The wallet's own name, as it announces itself.
  String get name;

  /// The wallet's logo as the wallet announced it, usually a `data:` URI.
  String? get icon;

  /// The standard the app reaches it through, for the UI: `EIP-6963`,
  /// `Wallet Standard`, ...
  String get via;

  /// The chain families it can sign for.
  Set<ChainFamily> get families;

  /// Asks the wallet for an account on [network]'s chain. The wallet shows
  /// its own prompt; the user picks an account and approves.
  ///
  /// [onLost] runs if the wallet later drops the connection or the user
  /// switches to another account in it, so the app stops using this one.
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost});
}

/// A signer for an account in an [InstalledWallet].
abstract class InstalledSigner implements WalletSigner {
  InstalledWallet get wallet;

  @override
  String get name => wallet.name;

  /// Lets the wallet forget this app, where it supports that.
  Future<void> disconnect() async {}
}

/// Thrown when the wallet refuses or fails a request.
class WalletException implements Exception {
  const WalletException(this.message, {this.code, this.declined = false});

  final String message;

  /// The wallet's error code, when it gave one. EIP-1193 wallets use 4001
  /// for "the user rejected" and 4902 for "unknown chain".
  final Object? code;

  /// The user said no in the wallet.
  final bool declined;

  @override
  String toString() => message;
}

/// Finds the wallets installed on this device.
///
/// Wallets announce themselves whenever they are ready, sometimes after the
/// app has started, so this is a [ChangeNotifier]: the list can grow.
abstract class WalletFinder extends ChangeNotifier {
  /// The finder for the platform the app runs on.
  static WalletFinder forThisPlatform() => platform.createFinder();

  List<InstalledWallet> get wallets;

  /// Starts listening for wallets. Safe to call more than once.
  void start();

  /// What to tell the user when no wallet was found for [family].
  String noneFoundHint(ChainFamily family);
}
