import '../wallet_signer.dart';
import 'installed_wallet.dart';
import 'web/eip6963.dart';
import 'web/keplr.dart';
import 'web/wallet_standard.dart';

WalletFinder createFinder() => WebWalletFinder();

/// Finds browser extension wallets through the standards they announce
/// themselves with.
class WebWalletFinder extends WalletFinder {
  final _wallets = <String, InstalledWallet>{};
  bool _started = false;

  @override
  List<InstalledWallet> get wallets => List.unmodifiable(_wallets.values);

  @override
  void start() {
    if (_started) return;
    _started = true;
    Eip6963.listen(_add);
    WalletStandard.listen(_add);
    KeplrWallets.listen(_add);
  }

  void _add(InstalledWallet wallet) {
    // Wallets may announce themselves more than once.
    if (_wallets.containsKey(wallet.id)) return;
    _wallets[wallet.id] = wallet;
    notifyListeners();
  }

  @override
  String noneFoundHint(ChainFamily family) => switch (family) {
    ChainFamily.evm => 'No EVM wallet extension found. Install MetaMask, Rabby or another, then reload this page.',
    ChainFamily.solana => 'No Solana wallet extension found. Install Phantom, Solflare or Backpack, then reload.',
    ChainFamily.sui => 'No Sui wallet extension found. Install Slush, then reload this page.',
    ChainFamily.cosmos => 'No Cosmos wallet extension found. Install Keplr or Leap, then reload this page.',
    // NEAR wallets have no page API to find them by. Each one ships its own
    // script for the near-connect selector, which runs it in a sandboxed
    // iframe: that is an SDK, not a standard.
    ChainFamily.near =>
      'NEAR browser wallets connect through their own scripts in the near-connect selector, not a page API, so '
          'there is nothing to find here. Use the in-app wallet, or an SDK (option 3).',
  };
}
