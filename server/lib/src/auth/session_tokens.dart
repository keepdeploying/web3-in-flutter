import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../chain_family.dart';
import 'sign_in_messages.dart';

/// Who signed in, and how. The app sends the token back on every request.
class Session {
  const Session({
    required this.family,
    required this.address,
    required this.chainId,
    required this.level,
    required this.issuedAt,
    required this.expiresAt,
  });

  final ChainFamily family;
  final String address;
  final String chainId;
  final SignInLevel level;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// One account per chain family: the same EVM address on Sepolia and Base
  /// is the same person.
  String get accountKey => '${family.name}:${family == ChainFamily.evm ? address.toLowerCase() : address}';

  Map<String, Object> toJson() => {
    'sub': address,
    'fam': family.name,
    'chain': chainId,
    'lvl': level.name,
    'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
    'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
  };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    family: ChainFamily.values.byName(json['fam'] as String),
    address: json['sub'] as String,
    chainId: json['chain'] as String,
    level: SignInLevel.values.byName(json['lvl'] as String),
    issuedAt: DateTime.fromMillisecondsSinceEpoch((json['iat'] as int) * 1000, isUtc: true),
    expiresAt: DateTime.fromMillisecondsSinceEpoch((json['exp'] as int) * 1000, isUtc: true),
  );
}

/// Issues and checks session tokens: JSON Web Tokens signed with HMAC-SHA256.
///
/// After the wallet signature is checked once, a token is cheaper than
/// asking for a signature on every request. Only the server knows [secret],
/// so only it can make a valid token.
class SessionTokens {
  SessionTokens({List<int>? secret, this.lifetime = const Duration(hours: 1), DateTime Function()? clock})
    : secret = secret ?? QuickCrypto.generateRandom(32),
      _now = clock ?? DateTime.now;

  final List<int> secret;
  final Duration lifetime;
  final DateTime Function() _now;

  static final _header = _encode({'alg': 'HS256', 'typ': 'JWT'});

  ({String token, Session session}) issue({
    required ChainFamily family,
    required String address,
    required String chainId,
    required SignInLevel level,
  }) {
    final now = _now().toUtc();
    final session = Session(
      family: family,
      address: address,
      chainId: chainId,
      level: level,
      issuedAt: now,
      expiresAt: now.add(lifetime),
    );
    final unsigned = '$_header.${_encode(session.toJson())}';
    return (token: '$unsigned.${_sign(unsigned)}', session: session);
  }

  /// The session in [token], or null if it was tampered with or expired.
  Session? read(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != _header) return null;
    // Any edit to the payload changes the signature. Compare in constant
    // time, so response timing doesn't leak how many characters matched.
    if (!_equalInConstantTime(_sign('${parts[0]}.${parts[1]}'), parts[2])) return null;
    try {
      final session = Session.fromJson(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))));
      return _now().isBefore(session.expiresAt) ? session : null;
    } on Object {
      return null;
    }
  }

  static bool _equalInConstantTime(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  String _sign(String data) => _base64Url(QuickCrypto.hmacsha256Hash(secret, utf8.encode(data)));

  static String _encode(Map<String, Object> json) => _base64Url(utf8.encode(jsonEncode(json)));

  // JWTs use base64url without padding.
  static String _base64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
