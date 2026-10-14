import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../wallet_signer.dart';
import 'installed_wallet.dart';
import 'mobile/mwa_wallet.dart';
import 'mobile/phantom_links.dart';

WalletFinder createFinder() => NativeWalletFinder();

/// Finds wallet apps on phones.
///
/// An app can ask the system whether another app handles a link: here
/// `phantom://`, `solflare://`, and on Android `solana-wallet:` for the
/// Mobile Wallet Adapter. Android only answers for the schemes listed in
/// the manifest's `<queries>`, and iOS for those in
/// `LSApplicationQueriesSchemes` (tool/setup_platforms.dart adds both).
///
/// Desktops have no such wallets: wallet extensions live in the browser.
class NativeWalletFinder extends WalletFinder {
  final _wallets = <InstalledWallet>[];
  bool _started = false;

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  List<InstalledWallet> get wallets => List.unmodifiable(_wallets);

  @override
  void start() {
    if (_started || !_mobile) return;
    _started = true;
    _look();
  }

  Future<void> _look() async {
    Future<bool> handles(String uri) => canLaunchUrl(Uri.parse(uri)).catchError((_) => false);
    if (Platform.isAndroid && await handles('solana-wallet:/v1/associate/local')) _wallets.add(MwaWallet());
    if (await handles('phantom://')) _wallets.add(PhantomLinkWallet.phantom());
    if (await handles('solflare://')) _wallets.add(PhantomLinkWallet.solflare());
    notifyListeners();
  }

  @override
  String noneFoundHint(ChainFamily family) {
    if (!_mobile) {
      return 'Desktop wallets live in the browser. Open the web version, or use an SDK (option 3).';
    }
    return switch (family) {
      ChainFamily.solana => 'No Solana wallet app found. Install Phantom or Solflare.',
      _ =>
        'Wallet apps for ${family.label} only talk to other apps through an SDK (option 3). You can also open '
            "the web version in a wallet's browser:",
    };
  }
}
