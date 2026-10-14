import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'vault.dart';

Vault createVault() => SecureStorageVault();

/// Stores the phrase in the operating system's credential store:
/// - Android: encrypted with a key held in the Android Keystore;
/// - iOS and macOS: the Keychain;
/// - Windows: the Credential Manager, protected with DPAPI;
/// - Linux: the Secret Service keyring (GNOME Keyring or KWallet), via libsecret.
///
/// Turning on device auth adds a fingerprint, face or PIN prompt before the
/// app reads the phrase. That prompt is a check in the app; real wallets go
/// further and bind the key itself to biometrics in secure hardware.
class SecureStorageVault implements Vault {
  SecureStorageVault({FlutterSecureStorage? storage, LocalAuthentication? auth})
    : _storage = storage ?? _defaultStorage,
      _auth = auth ?? LocalAuthentication();

  // On macOS, the legacy keychain needs no provisioning profile, so the app
  // runs on any Mac, signed or not.
  static const _defaultStorage = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

  static const _phraseKey = 'recovery_phrase';
  static const _deviceAuthKey = 'require_device_auth';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  @override
  String get storageName => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android encrypted storage, with its key in the Android Keystore',
    TargetPlatform.iOS => 'the iOS Keychain',
    TargetPlatform.macOS => 'the macOS Keychain',
    TargetPlatform.windows => 'the Windows Credential Manager',
    TargetPlatform.linux => 'the system keyring, through libsecret',
    _ => 'the system credential store',
  };

  @override
  bool get usesPassword => false;

  @override
  Future<bool> hasWallet() => _storage.containsKey(key: _phraseKey);

  @override
  Future<bool> canUseDeviceAuth() async {
    try {
      return await _auth.isDeviceSupported();
    } on MissingPluginException {
      return false; // Linux: local_auth has no implementation.
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> save(String phrase, VaultOptions options) async {
    await _storage.write(key: _phraseKey, value: phrase);
    await _storage.write(key: _deviceAuthKey, value: '${options.requireDeviceAuth}');
  }

  Future<bool> _requiresDeviceAuth() async => await _storage.read(key: _deviceAuthKey) == 'true';

  @override
  Future<String?> resume() async {
    if (await _requiresDeviceAuth()) return null;
    return _storage.read(key: _phraseKey);
  }

  @override
  Future<String> unlock({String? password}) async {
    if (await _requiresDeviceAuth()) {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your Flutter Counter wallet',
        persistAcrossBackgrounding: true,
      );
      if (!ok) throw UnlockCancelledException();
    }
    final phrase = await _storage.read(key: _phraseKey);
    if (phrase == null) throw StateError('No wallet saved');
    return phrase;
  }

  @override
  Future<void> lock() async {}

  @override
  Future<void> delete() async {
    await _storage.delete(key: _phraseKey);
    await _storage.delete(key: _deviceAuthKey);
  }
}
