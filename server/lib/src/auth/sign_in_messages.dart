import '../chain_family.dart';

/// How much a sign-in message protects you. The app has a switch to compare
/// the three.
enum SignInLevel {
  /// The same text every time. Anyone who sees one signature (a log, a
  /// leaked request) can replay it and sign in as you, forever.
  fixed,

  /// Adds a one-time nonce from the server, so a signature works once.
  /// But the message doesn't say which site it is for: a phishing site can
  /// fetch a nonce from the real server, ask you to sign, and use it.
  nonce,

  /// A structured message in the style of Sign-In with Ethereum (EIP-4361):
  /// the site's domain, your address, the chain, the nonce and an expiry.
  /// Wallets can warn when the domain doesn't match the site asking.
  standard,
}

/// Who the app is, as written into level 3 messages.
class AppIdentity {
  const AppIdentity({
    this.domain = 'flutter-counter.app',
    this.uri = 'https://flutter-counter.app',
    this.statement = 'Sign in to Flutter Counter.',
  });

  final String domain;
  final String uri;
  final String statement;
}

/// Builds and reads the sign-in messages for each level.
abstract final class SignInMessages {
  static const fixedText = 'Sign in to Flutter Counter';

  static String fixed() => fixedText;

  static String withNonce(String nonce) => '$fixedText\n\nNonce: $nonce';

  /// The account name in the first line. EIP-4361 says "Ethereum account"
  /// for every EVM chain; the Solana (SIWS), Sui and Cosmos variants use
  /// their own names with the same layout.
  static String accountName(ChainFamily family) => switch (family) {
    ChainFamily.evm => 'Ethereum',
    ChainFamily.solana => 'Solana',
    ChainFamily.sui => 'Sui',
    ChainFamily.cosmos => 'Cosmos',
    ChainFamily.near => 'NEAR',
  };

  static String standard(StandardMessage m) => [
    '${m.domain} wants you to sign in with your ${accountName(m.family)} account:',
    m.address,
    '',
    m.statement,
    '',
    'URI: ${m.uri}',
    'Version: 1',
    'Chain ID: ${m.chainId}',
    'Nonce: ${m.nonce}',
    'Issued At: ${m.issuedAt.toUtc().toIso8601String()}',
    'Expiration Time: ${m.expiresAt.toUtc().toIso8601String()}',
  ].join('\n');

  /// Reads the nonce out of a level 2 message, or null if it isn't one.
  static String? parseNonce(String message) =>
      RegExp('^${RegExp.escape(fixedText)}\\n\\nNonce: ([A-Za-z0-9]+)\$').firstMatch(message)?.group(1);

  /// Reads a level 3 message back into its fields, or null if it doesn't
  /// have the expected layout. The server never trusts what it reads: it
  /// compares every field with what it expects.
  static StandardMessage? parseStandard(String message) {
    final lines = message.split('\n');
    if (lines.length != 11 || lines[2].isNotEmpty || lines[4].isNotEmpty) return null;
    final header = RegExp(r'^(\S+) wants you to sign in with your (\S+) account:$').firstMatch(lines[0]);
    if (header == null) return null;
    final family = ChainFamily.values.where((f) => accountName(f) == header.group(2)).firstOrNull;
    String? field(int line, String name) =>
        lines[line].startsWith('$name: ') ? lines[line].substring(name.length + 2) : null;
    final uri = field(5, 'URI');
    final version = field(6, 'Version');
    final chainId = field(7, 'Chain ID');
    final nonce = field(8, 'Nonce');
    final issuedAt = DateTime.tryParse(field(9, 'Issued At') ?? '');
    final expiresAt = DateTime.tryParse(field(10, 'Expiration Time') ?? '');
    if (family == null || uri == null || version != '1' || chainId == null || nonce == null) return null;
    if (issuedAt == null || expiresAt == null) return null;
    return StandardMessage(
      domain: header.group(1)!,
      family: family,
      address: lines[1],
      statement: lines[3],
      uri: uri,
      chainId: chainId,
      nonce: nonce,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }
}

/// The fields of a level 3 message.
class StandardMessage {
  const StandardMessage({
    required this.domain,
    required this.family,
    required this.address,
    required this.statement,
    required this.uri,
    required this.chainId,
    required this.nonce,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String domain;
  final ChainFamily family;
  final String address;
  final String statement;
  final String uri;
  final String chainId;
  final String nonce;
  final DateTime issuedAt;
  final DateTime expiresAt;
}
