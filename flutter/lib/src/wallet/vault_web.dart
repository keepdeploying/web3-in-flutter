import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'vault.dart';

Vault createVault() => WebVault();

/// Stores the phrase in the browser, encrypted with your password.
///
/// Browsers have no keychain an app can use, so this vault builds one from
/// WebCrypto and IndexedDB:
/// 1. PBKDF2 (SHA-256, [iterations] rounds, a random salt) turns the
///    password into an AES-GCM key. The many rounds make guessing slow.
/// 2. AES-GCM encrypts the phrase with that key and a random IV.
/// 3. The ciphertext, salt and IV go into IndexedDB. The password and the
///    key are never stored.
///
/// "Stay unlocked" adds a second copy, encrypted with a random AES key that
/// WebCrypto creates as non-extractable: the page can use it, but even the
/// page's own code can't read its bytes. That key object is saved in
/// IndexedDB too, so a reload can decrypt without the password.
///
/// This protects the phrase at rest (a copied browser profile, a stolen
/// laptop with the browser closed). It does not protect against malicious
/// code running inside the page, which can do anything the app can.
class WebVault implements Vault {
  WebVault({this.iterations = 600000, this.databaseName = 'flutter_counter_wallet'});

  /// OWASP's recommendation for PBKDF2-HMAC-SHA256 (2023).
  final int iterations;
  final String databaseName;

  static const _store = 'vault';
  static const _passwordRecord = 'password';
  static const _sessionRecord = 'session';

  web.SubtleCrypto get _subtle => web.window.crypto.subtle;

  @override
  String get storageName => 'this browser (IndexedDB), encrypted with your password';

  @override
  bool get usesPassword => true;

  @override
  Future<bool> hasWallet() async => await _get(_passwordRecord) != null;

  @override
  Future<bool> canUseDeviceAuth() async => false;

  @override
  Future<void> save(String phrase, VaultOptions options) async {
    final password = options.password;
    if (password == null || password.isEmpty) throw ArgumentError('The web vault needs a password');
    final salt = _random(16);
    final key = await _passwordKey(password, salt, iterations);
    final iv = _random(12);
    await _put(
      _passwordRecord,
      _VaultRecord(
        salt: salt.toJS,
        iv: iv.toJS,
        data: (await _encrypt(key, iv, utf8.encode(phrase))).toJS,
        iterations: iterations,
      ),
    );
    if (options.stayUnlocked) {
      await _saveSession(phrase);
    } else {
      await lock();
    }
  }

  @override
  Future<String?> resume() async {
    final record = await _get(_sessionRecord) as _SessionRecord?;
    if (record == null) return null;
    try {
      return utf8.decode(await _decrypt(record.key, record.iv.toDart, record.data.toDart));
    } catch (_) {
      await lock(); // The session can't be used any more: ask for the password.
      return null;
    }
  }

  @override
  Future<String> unlock({String? password}) async {
    final record = await _get(_passwordRecord) as _VaultRecord?;
    if (record == null) throw StateError('No wallet saved');
    if (password == null) throw WrongPasswordException();
    final key = await _passwordKey(password, record.salt.toDart, record.iterations);
    try {
      return utf8.decode(await _decrypt(key, record.iv.toDart, record.data.toDart));
    } catch (_) {
      // AES-GCM checks an authentication tag, so a wrong key fails loudly
      // instead of returning garbage.
      throw WrongPasswordException();
    }
  }

  /// Keeps the phrase unlockable without a password, until [lock].
  Future<void> _saveSession(String phrase) async {
    final key =
        await _subtle
                .generateKey(
                  _AesKeyGenParams(name: 'AES-GCM', length: 256),
                  false, // Not extractable: its bytes can never leave WebCrypto.
                  ['encrypt'.toJS, 'decrypt'.toJS].toJS,
                )
                .toDart
            as web.CryptoKey;
    final iv = _random(12);
    final data = await _encrypt(key, iv, utf8.encode(phrase));
    await _put(_sessionRecord, _SessionRecord(key: key, iv: iv.toJS, data: data.toJS));
  }

  @override
  Future<void> lock() => _delete(_sessionRecord);

  @override
  Future<void> delete() async {
    await _delete(_sessionRecord);
    await _delete(_passwordRecord);
  }

  // WebCrypto.

  Future<web.CryptoKey> _passwordKey(String password, Uint8List salt, int iterations) async {
    final material = await _subtle
        .importKey('raw', utf8.encode(password).toJS, 'PBKDF2'.toJS, false, ['deriveKey'.toJS].toJS)
        .toDart;
    final key = await _subtle
        .deriveKey(
          _Pbkdf2Params(name: 'PBKDF2', salt: salt.toJS, iterations: iterations, hash: 'SHA-256'),
          material,
          _AesKeyGenParams(name: 'AES-GCM', length: 256),
          false,
          ['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart;
    return key as web.CryptoKey;
  }

  Future<Uint8List> _encrypt(web.CryptoKey key, Uint8List iv, List<int> plain) async {
    final result = await _subtle
        .encrypt(_AesGcmParams(name: 'AES-GCM', iv: iv.toJS), key, Uint8List.fromList(plain).toJS)
        .toDart;
    return (result as JSArrayBuffer).toDart.asUint8List();
  }

  Future<Uint8List> _decrypt(web.CryptoKey key, Uint8List iv, Uint8List data) async {
    final result = await _subtle.decrypt(_AesGcmParams(name: 'AES-GCM', iv: iv.toJS), key, data.toJS).toDart;
    return (result as JSArrayBuffer).toDart.asUint8List();
  }

  static Uint8List _random(int length) {
    // On the web, Random.secure() uses crypto.getRandomValues.
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  // IndexedDB. Its API predates promises, so each request is wrapped in a
  // Completer that its success and error events complete.

  web.IDBDatabase? _db;

  Future<web.IDBDatabase> _open() async {
    if (_db != null) return _db!;
    final request = web.window.indexedDB.open(databaseName, 1);
    request.onupgradeneeded = (web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }.toJS;
    return _db = await _done(request) as web.IDBDatabase;
  }

  Future<web.IDBObjectStore> _objectStore(String mode) async =>
      (await _open()).transaction(_store.toJS, mode).objectStore(_store);

  Future<JSAny?> _get(String key) async => _done((await _objectStore('readonly')).get(key.toJS));

  Future<void> _put(String key, JSAny value) async => _done((await _objectStore('readwrite')).put(value, key.toJS));

  Future<void> _delete(String key) async => _done((await _objectStore('readwrite')).delete(key.toJS));

  static Future<JSAny?> _done(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = (web.Event _) {
      completer.complete(request.result);
    }.toJS;
    request.onerror = (web.Event _) {
      completer.completeError(StateError('IndexedDB: ${request.error?.message}'));
    }.toJS;
    return completer.future;
  }
}

// JavaScript object literals for WebCrypto parameters and stored records.

extension type _Pbkdf2Params._(JSObject _) implements JSObject {
  external factory _Pbkdf2Params({String name, JSUint8Array salt, int iterations, String hash});
}

extension type _AesKeyGenParams._(JSObject _) implements JSObject {
  external factory _AesKeyGenParams({String name, int length});
}

extension type _AesGcmParams._(JSObject _) implements JSObject {
  external factory _AesGcmParams({String name, JSUint8Array iv});
}

extension type _VaultRecord._(JSObject _) implements JSObject {
  external factory _VaultRecord({JSUint8Array salt, JSUint8Array iv, JSUint8Array data, int iterations});
  external JSUint8Array get salt;
  external JSUint8Array get iv;
  external JSUint8Array get data;
  external int get iterations;
}

extension type _SessionRecord._(JSObject _) implements JSObject {
  external factory _SessionRecord({web.CryptoKey key, JSUint8Array iv, JSUint8Array data});
  external web.CryptoKey get key;
  external JSUint8Array get iv;
  external JSUint8Array get data;
}
