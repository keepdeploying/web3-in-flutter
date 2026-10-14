import 'vault_native.dart' if (dart.library.js_interop) 'vault_web.dart' as platform;

/// Where the in-app wallet keeps its recovery phrase.
///
/// Each platform has its own safe place:
/// - Android, iOS, macOS, Windows and Linux: the operating system's
///   credential store, through `flutter_secure_storage` ([platform] native);
/// - the web: there is no such store, so the phrase is encrypted with a key
///   made from your password and saved in IndexedDB ([platform] web).
///
/// The app only keeps the derived keys in memory while unlocked.
abstract class Vault {
  /// The vault for the platform the app runs on.
  static Vault forThisPlatform() => platform.createVault();

  /// A short description of where the phrase is stored, for the UI.
  String get storageName;

  /// Whether unlocking needs a password typed by the user (the web).
  bool get usesPassword;

  Future<bool> hasWallet();

  /// Whether this device can ask for a fingerprint, face or device PIN.
  Future<bool> canUseDeviceAuth();

  /// Saves the phrase, replacing any saved before.
  Future<void> save(String phrase, VaultOptions options);

  /// Unlocks without asking anything, if the user allowed that: the web
  /// vault's "stay unlocked", or a native vault without device auth.
  /// Returns null when the user has to unlock by hand.
  Future<String?> resume();

  /// Unlocks by asking the user: their password on the web, or a
  /// fingerprint, face or device PIN where they turned that on.
  ///
  /// Throws [WrongPasswordException] or [UnlockCancelledException].
  Future<String> unlock({String? password});

  /// Forgets anything that would unlock without asking (the web session key).
  Future<void> lock();

  /// Deletes the saved phrase for good.
  Future<void> delete();
}

class VaultOptions {
  const VaultOptions({this.password, this.stayUnlocked = false, this.requireDeviceAuth = false});

  /// Web only: encrypts the phrase.
  final String? password;

  /// Web only: keep a session key so reloading the page doesn't ask again.
  final bool stayUnlocked;

  /// Native only: ask for a fingerprint, face or device PIN to unlock.
  final bool requireDeviceAuth;
}

class WrongPasswordException implements Exception {
  @override
  String toString() => 'Wrong password';
}

class UnlockCancelledException implements Exception {
  @override
  String toString() => 'Unlock cancelled';
}

/// Keeps the phrase in memory only. For tests, and as a fallback when the
/// platform store is missing (for example Linux without a keyring).
class MemoryVault implements Vault {
  String? _phrase;
  VaultOptions _options = const VaultOptions();
  bool _unlockedSession = false;

  @override
  String get storageName => 'memory only (lost when the app closes)';

  @override
  bool get usesPassword => false;

  @override
  Future<bool> hasWallet() async => _phrase != null;

  @override
  Future<bool> canUseDeviceAuth() async => false;

  @override
  Future<void> save(String phrase, VaultOptions options) async {
    _phrase = phrase;
    _options = options;
    _unlockedSession = true;
  }

  @override
  Future<String?> resume() async => _unlockedSession && !_options.requireDeviceAuth ? _phrase : null;

  @override
  Future<String> unlock({String? password}) async {
    if (_phrase == null) throw StateError('No wallet');
    if (_options.password != null && password != _options.password) throw WrongPasswordException();
    _unlockedSession = true;
    return _phrase!;
  }

  @override
  Future<void> lock() async => _unlockedSession = false;

  @override
  Future<void> delete() async {
    _phrase = null;
    _unlockedSession = false;
  }
}
