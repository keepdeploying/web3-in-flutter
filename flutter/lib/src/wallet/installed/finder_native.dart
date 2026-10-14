import '../wallet_signer.dart';
import 'installed_wallet.dart';

WalletFinder createFinder() => NativeWalletFinder();

/// Finds wallet apps on phones and desktops.
class NativeWalletFinder extends WalletFinder {
  @override
  List<InstalledWallet> get wallets => const [];

  @override
  void start() {}

  @override
  String noneFoundHint(ChainFamily family) =>
      'No wallet app found for ${family.label} on this device. Browser extensions work in the web version.';
}
