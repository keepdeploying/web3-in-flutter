import 'package:flutter/foundation.dart';

import '../chains/networks.dart';
import '../wallet/installed/installed_wallet.dart';
import '../wallet/wallet_signer.dart';

export '../wallet/installed/installed_wallet.dart';

/// Installed wallets: the ones found on this device, and the accounts
/// connected from them, one per chain family.
///
/// A connected account takes over from the in-app wallet for its family,
/// for sign-in and writes, until it is disconnected.
class ConnectionController extends ChangeNotifier {
  ConnectionController({WalletFinder? finder}) : finder = finder ?? WalletFinder.forThisPlatform() {
    this.finder.addListener(notifyListeners);
    this.finder.start();
  }

  final WalletFinder finder;

  final _connected = <ChainFamily, InstalledSigner>{};

  /// The wallet a connection is waiting on, if any.
  InstalledWallet? connecting;

  /// Why the last connection failed.
  String? error;

  /// The connected account for [family], if any.
  InstalledSigner? signerFor(ChainFamily family) => _connected[family];

  List<InstalledWallet> walletsFor(ChainFamily family) => [
    for (final wallet in finder.wallets)
      if (wallet.families.contains(family)) wallet,
  ];

  Future<void> connect(InstalledWallet wallet, Network network) async {
    connecting = wallet;
    error = null;
    notifyListeners();
    try {
      final family = network.family;
      late final InstalledSigner signer;
      signer = await wallet.connect(
        network,
        onLost: () {
          if (_connected[family] != signer) return;
          _connected.remove(family);
          notifyListeners();
        },
      );
      await _connected[family]?.disconnect();
      _connected[family] = signer;
    } on WalletException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      connecting = null;
      notifyListeners();
    }
  }

  Future<void> disconnect(ChainFamily family) async {
    final signer = _connected.remove(family);
    notifyListeners();
    await signer?.disconnect();
  }
}
