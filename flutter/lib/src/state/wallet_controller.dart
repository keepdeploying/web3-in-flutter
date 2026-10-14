import 'package:flutter/foundation.dart';

import '../wallet/hd_keys.dart';
import '../wallet/in_app_signer.dart';
import '../wallet/vault.dart';
import '../wallet/wallet_signer.dart';

enum WalletStatus {
  /// Checking the vault at startup.
  loading,

  /// No wallet on this device yet.
  none,

  /// A wallet is saved, but its keys aren't in memory.
  locked,

  /// Keys are in memory and the app can sign.
  unlocked,
}

/// The in-app wallet: creates or imports a recovery phrase, saves it in the
/// [Vault], and while unlocked, holds the derived keys for every chain.
class WalletController extends ChangeNotifier {
  WalletController({Vault? vault}) : _vault = vault ?? Vault.forThisPlatform();

  Vault _vault;
  Vault get vault => _vault;

  /// Why the platform store couldn't be used, if it couldn't.
  String? vaultProblem;

  WalletStatus _status = WalletStatus.loading;
  WalletStatus get status => _status;

  Map<ChainFamily, ChainKey> _keys = const {};

  /// The key for [family], while unlocked.
  ChainKey? keyFor(ChainFamily family) => _keys[family];

  /// A signer for [family], while unlocked.
  WalletSigner? signerFor(ChainFamily family) {
    final key = _keys[family];
    return key == null ? null : InAppSigner(key);
  }

  /// Checks for a saved wallet, and unlocks it if that needs no prompt.
  Future<void> start() async {
    try {
      if (!await vault.hasWallet()) return _set(WalletStatus.none);
      final phrase = await vault.resume();
      phrase == null ? _set(WalletStatus.locked) : _load(phrase);
    } catch (e) {
      // The platform store failed, for example Linux without a running
      // keyring. Fall back to memory, and tell the user.
      debugPrint('Wallet vault unavailable: $e');
      vaultProblem = '$e';
      _vault = MemoryVault();
      _set(WalletStatus.none);
    }
  }

  /// Saves a new or imported phrase and unlocks it.
  Future<void> save(String phrase, VaultOptions options) async {
    if (!HdKeys.isValidMnemonic(phrase)) throw ArgumentError('Not a valid recovery phrase');
    await vault.save(HdKeys.normalize(phrase), options);
    _load(HdKeys.normalize(phrase));
  }

  /// For when the platform store fails, for example Linux without a
  /// keyring: keeps the wallet in memory until the app closes.
  Future<void> saveInMemory(String phrase) async {
    _vault = MemoryVault();
    await save(phrase, const VaultOptions());
  }

  /// Throws [WrongPasswordException] or [UnlockCancelledException].
  Future<void> unlock({String? password}) async => _load(await vault.unlock(password: password));

  Future<void> lock() async {
    await vault.lock();
    _keys = const {};
    _set(WalletStatus.locked);
  }

  /// Asks for the password or device auth again, then returns the phrase.
  Future<String> revealPhrase({String? password}) => vault.unlock(password: password);

  Future<void> remove() async {
    await vault.delete();
    _keys = const {};
    _set(WalletStatus.none);
  }

  void _load(String phrase) {
    // Derive every chain's key once. The phrase string itself isn't kept.
    // (Dart can't wipe a String from memory, one of the limits of a demo
    // wallet compared with one that keeps keys in secure hardware.)
    _keys = HdKeys.deriveAll(phrase);
    _set(WalletStatus.unlocked);
  }

  void _set(WalletStatus status) {
    _status = status;
    notifyListeners();
  }
}
