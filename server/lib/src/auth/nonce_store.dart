import 'package:blockchain_utils/blockchain_utils.dart';

import '../chain_family.dart';

/// What the server remembers about a nonce it handed out.
class IssuedNonce {
  IssuedNonce({
    required this.value,
    required this.family,
    required this.address,
    required this.chainId,
    required this.expiresAt,
  });

  /// Base58 text of 32 random bytes. On NEAR the same bytes are the
  /// NEP-413 nonce.
  final String value;
  final ChainFamily family;
  final String address;
  final String chainId;
  final DateTime expiresAt;
  bool used = false;

  List<int> get bytes => Base58Decoder.decode(value);
}

enum NonceCheck {
  ok('The nonce was issued by this server for this account, and not used before.'),
  unknown('This server never issued that nonce (or forgot it after a restart).'),
  otherAccount('That nonce was issued for another account or chain.'),
  used('That nonce was already used: this is a replay.'),
  expired('That nonce expired. Get a fresh challenge and sign again.');

  const NonceCheck(this.explanation);
  final String explanation;
}

/// Hands out one-time nonces and remembers them until they expire.
///
/// In memory, which is fine for a demo and a single server. A real backend
/// with several instances keeps them in a shared store such as Redis.
class NonceStore {
  NonceStore({this.lifetime = const Duration(minutes: 5), DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final Duration lifetime;
  final DateTime Function() _now;
  final _nonces = <String, IssuedNonce>{};

  IssuedNonce issue({required ChainFamily family, required String address, required String chainId}) {
    final now = _now();
    _nonces.removeWhere((_, n) => n.expiresAt.isBefore(now));
    final nonce = IssuedNonce(
      value: Base58Encoder.encode(QuickCrypto.generateRandom(32)),
      family: family,
      address: address,
      chainId: chainId,
      expiresAt: now.add(lifetime),
    );
    _nonces[nonce.value] = nonce;
    return nonce;
  }

  IssuedNonce? find(String value) => _nonces[value];

  /// Checks the nonce and, only if everything is right, marks it used.
  NonceCheck consume(String value, {required ChainFamily family, required String address}) {
    final nonce = _nonces[value];
    if (nonce == null) return NonceCheck.unknown;
    if (nonce.family != family || nonce.address.toLowerCase() != address.toLowerCase()) return NonceCheck.otherAccount;
    if (nonce.used) return NonceCheck.used;
    if (!_now().isBefore(nonce.expiresAt)) return NonceCheck.expired;
    nonce.used = true;
    return NonceCheck.ok;
  }
}
