import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

/// NaCl's `box`: how Phantom and Solflare encrypt what travels in deep links.
///
/// A deep link passes through the operating system and can be read by other
/// apps, so the app and the wallet agree on a key first (X25519, like a
/// Diffie-Hellman handshake), then encrypt every payload with it
/// (XSalsa20 to hide it, Poly1305 to detect tampering). This is the
/// `nacl.box` from TweetNaCl, which the wallets use, in plain Dart.
class NaclBox {
  NaclBox._(this._key);

  /// Agrees on the shared key from our secret key and their public key, as
  /// `nacl.box.before` does: X25519, then HSalsa20 to mix the result.
  factory NaclBox.between(List<int> mySecretKey, List<int> theirPublicKey) =>
      NaclBox._(_hsalsa20(X25519.scalarMult(mySecretKey, theirPublicKey), List.filled(16, 0)));

  final List<int> _key;

  /// A new X25519 key pair for one session with a wallet.
  static ({List<int> secretKey, List<int> publicKey}) newKeyPair() {
    final secret = QuickCrypto.generateRandom(32);
    final pair = X25519.scalarMultBase(secret);
    return (secretKey: pair.privateKey, publicKey: pair.publicKey);
  }

  /// A random 24-byte nonce. Each message needs its own.
  static List<int> newNonce() => QuickCrypto.generateRandom(24);

  /// Encrypts [message]: a 16-byte tag, then the ciphertext.
  List<int> seal(List<int> message, List<int> nonce) {
    final stream = _xsalsa20(_key, nonce, 32 + message.length);
    final cipher = [for (var i = 0; i < message.length; i++) message[i] ^ stream[32 + i]];
    return [...Poly1305.auth(stream.sublist(0, 32), cipher), ...cipher];
  }

  /// Decrypts what [seal] made, or returns null if it was changed.
  List<int>? open(List<int> sealed, List<int> nonce) {
    if (sealed.length < 16) return null;
    final cipher = sealed.sublist(16);
    final stream = _xsalsa20(_key, nonce, 32 + cipher.length);
    if (!BytesUtils.bytesEqual(Poly1305.auth(stream.sublist(0, 32), cipher), sealed.sublist(0, 16))) return null;
    return [for (var i = 0; i < cipher.length; i++) cipher[i] ^ stream[32 + i]];
  }

  // Salsa20 works on sixteen 32-bit words. Every operation is masked to 32
  // bits, so it gives the same results on the web, where ints are doubles.

  static int _rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xffffffff;

  static List<int> _words(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return [for (var i = 0; i < bytes.length; i += 4) data.getUint32(i, Endian.little)];
  }

  static const _sigma = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]; // "expand 32-byte k"

  /// The Salsa20 state: constants, key, and 16 bytes of nonce and counter.
  static List<int> _state(List<int> key, List<int> input16) {
    final k = _words(key), n = _words(input16);
    return [
      _sigma[0],
      k[0],
      k[1],
      k[2],
      k[3],
      _sigma[1],
      n[0],
      n[1],
      n[2],
      n[3],
      _sigma[2],
      k[4],
      k[5],
      k[6],
      k[7],
      _sigma[3],
    ];
  }

  /// 20 rounds of Salsa20 on [x], in place.
  static void _rounds(List<int> x) {
    void quarter(int a, int b, int c, int d) {
      x[b] ^= _rotl((x[a] + x[d]) & 0xffffffff, 7);
      x[c] ^= _rotl((x[b] + x[a]) & 0xffffffff, 9);
      x[d] ^= _rotl((x[c] + x[b]) & 0xffffffff, 13);
      x[a] ^= _rotl((x[d] + x[c]) & 0xffffffff, 18);
    }

    for (var i = 0; i < 10; i++) {
      // Columns, then rows.
      quarter(0, 4, 8, 12);
      quarter(5, 9, 13, 1);
      quarter(10, 14, 2, 6);
      quarter(15, 3, 7, 11);
      quarter(0, 1, 2, 3);
      quarter(5, 6, 7, 4);
      quarter(10, 11, 8, 9);
      quarter(15, 12, 13, 14);
    }
  }

  static List<int> _bytes(List<int> words) {
    final data = ByteData(words.length * 4);
    for (var i = 0; i < words.length; i++) {
      data.setUint32(i * 4, words[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  /// HSalsa20: Salsa20's rounds without the final addition, keeping words
  /// 0, 5, 10, 15, 6, 7, 8 and 9. Turns a key and 16 bytes into a new key.
  static List<int> _hsalsa20(List<int> key, List<int> input16) {
    final x = _state(key, input16);
    _rounds(x);
    return _bytes([x[0], x[5], x[10], x[15], x[6], x[7], x[8], x[9]]);
  }

  /// XSalsa20's key stream: HSalsa20 makes a subkey from the first 16 nonce
  /// bytes, then Salsa20 runs with the last 8 and a block counter.
  static List<int> _xsalsa20(List<int> key, List<int> nonce, int length) {
    final subkey = _hsalsa20(key, nonce.sublist(0, 16));
    final out = <int>[];
    for (var block = 0; out.length < length; block++) {
      // The counter is a 64-bit little-endian number; two words.
      final counter = _bytes([block, 0]);
      final input = _state(subkey, [...nonce.sublist(16, 24), ...counter]);
      final x = [...input];
      _rounds(x);
      out.addAll(_bytes([for (var i = 0; i < 16; i++) (x[i] + input[i]) & 0xffffffff]));
    }
    return out.sublist(0, length);
  }
}
