import 'dart:convert';

import '../chain_family.dart';
import '../signing/signed_message.dart';
import 'description_store.dart';
import 'nonce_store.dart';
import 'session_tokens.dart';
import 'sign_in_messages.dart';
import 'signature_verifier.dart';

/// What the app asks for before signing in.
class ChallengeRequest {
  const ChallengeRequest({required this.level, required this.family, required this.address, required this.chainId});

  final SignInLevel level;
  final ChainFamily family;
  final String address;

  /// The network's chain ID: "11155111" for Sepolia, "devnet", "osmo-test-5"...
  final String chainId;

  Map<String, String> toJson() => {'level': level.name, 'family': family.name, 'address': address, 'chainId': chainId};

  factory ChallengeRequest.fromJson(Map<String, dynamic> json) => ChallengeRequest(
    level: SignInLevel.values.byName(json['level'] as String),
    family: ChainFamily.values.byName(json['family'] as String),
    address: json['address'] as String,
    chainId: json['chainId'] as String,
  );
}

/// The message to sign, from the server.
class Challenge {
  const Challenge({required this.level, required this.message, this.nonce, this.expiresAt, this.nearNonce});

  final SignInLevel level;
  final String message;

  /// Levels 2 and 3.
  final String? nonce;
  final DateTime? expiresAt;

  /// NEAR, level 3: the 32 bytes to pass as the NEP-413 nonce (base64).
  final String? nearNonce;

  Map<String, String> toJson() => {
    'level': level.name,
    'message': message,
    'nonce': ?nonce,
    'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
    'nearNonce': ?nearNonce,
  };

  factory Challenge.fromJson(Map<String, dynamic> json) => Challenge(
    level: SignInLevel.values.byName(json['level'] as String),
    message: json['message'] as String,
    nonce: json['nonce'] as String?,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    nearNonce: json['nearNonce'] as String?,
  );
}

/// One check the server made, for the app to show.
class Check {
  const Check(this.label, this.passed, this.detail);

  final String label;
  final bool passed;
  final String detail;

  Map<String, Object> toJson() => {'label': label, 'passed': passed, 'detail': detail};

  factory Check.fromJson(Map<String, dynamic> json) =>
      Check(json['label'] as String, json['passed'] as bool, json['detail'] as String);
}

/// The answer to a sign-in attempt: every check, and a session if all passed.
class SignInResult {
  const SignInResult({required this.checks, this.token, this.session});

  final List<Check> checks;
  final String? token;
  final Session? session;

  bool get ok => token != null;

  /// The first failed check, to show as the reason.
  Check? get failure => checks.where((c) => !c.passed).firstOrNull;

  Map<String, Object> toJson() => {
    'checks': [for (final c in checks) c.toJson()],
    'token': ?token,
    'session': ?session?.toJson(),
  };

  factory SignInResult.fromJson(Map<String, dynamic> json) => SignInResult(
    checks: [for (final c in json['checks'] as List) Check.fromJson(c as Map<String, dynamic>)],
    token: json['token'] as String?,
    session: json['session'] == null ? null : Session.fromJson(json['session'] as Map<String, dynamic>),
  );
}

/// Thrown when a request needs a session and has none (HTTP 401).
class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message = 'Sign in first.']);
  final String message;
  @override
  String toString() => message;
}

/// The whole backend: challenges, sign-in, sessions and descriptions.
///
/// Pure Dart, so it runs the same inside the app (LocalBackend) and behind
/// HTTP (bin/server.dart).
class CounterServer {
  CounterServer({
    SignatureVerifier? verifier,
    this.identity = const AppIdentity(),
    List<int>? sessionSecret,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now,
       verifier = verifier ?? SignatureVerifier(nearRecipient: identity.domain),
       nonces = NonceStore(clock: clock),
       sessions = SessionTokens(secret: sessionSecret, clock: clock),
       descriptions = DescriptionStore(clock: clock);

  final AppIdentity identity;
  final SignatureVerifier verifier;
  final NonceStore nonces;
  final SessionTokens sessions;
  final DescriptionStore descriptions;
  final DateTime Function() _now;

  /// How far a client's clock may be ahead of the server's.
  static const clockSkew = Duration(minutes: 1);

  Challenge challenge(ChallengeRequest request) {
    if (request.level == SignInLevel.fixed) {
      return Challenge(level: request.level, message: SignInMessages.fixed());
    }
    final nonce = nonces.issue(family: request.family, address: request.address, chainId: request.chainId);
    final message = request.level == SignInLevel.nonce
        ? SignInMessages.withNonce(nonce.value)
        : SignInMessages.standard(
            StandardMessage(
              domain: identity.domain,
              family: request.family,
              address: request.address,
              statement: identity.statement,
              uri: identity.uri,
              chainId: request.chainId,
              nonce: nonce.value,
              issuedAt: _now(),
              expiresAt: nonce.expiresAt,
            ),
          );
    return Challenge(
      level: request.level,
      message: message,
      nonce: nonce.value,
      expiresAt: nonce.expiresAt,
      nearNonce: request.family == ChainFamily.near && request.level == SignInLevel.standard
          ? _base64(nonce.bytes)
          : null,
    );
  }

  /// Checks a signed challenge. [chainId] is the network the app is on.
  Future<SignInResult> signIn(SignedMessage signed, {required SignInLevel level, required String chainId}) async {
    final checks = <Check>[];
    bool check(String label, bool passed, String detail) {
      checks.add(Check(label, passed, detail));
      return passed;
    }

    SignInResult fail() => SignInResult(checks: checks);

    // 1. The signature: always first, so nobody can burn other people's
    //    nonces with made-up signatures.
    final verification = await verifier.verify(signed, evmChainId: signed.family == ChainFamily.evm ? chainId : null);
    if (!check('Signature', verification.valid, verification.valid ? verification.how : verification.reason!)) {
      return fail();
    }

    // 2. The message: what each level adds.
    switch (level) {
      case SignInLevel.fixed:
        if (!check(
          'Message',
          signed.message == SignInMessages.fixedText,
          signed.message == SignInMessages.fixedText
              ? 'It is the fixed sign-in text. That is all level 1 checks, so an old signature works just as well.'
              : 'Level 1 expects exactly "${SignInMessages.fixedText}".',
        )) {
          return fail();
        }

      case SignInLevel.nonce:
        final nonce = SignInMessages.parseNonce(signed.message);
        if (!check('Message', nonce != null, nonce != null ? 'It has a nonce.' : 'Expected the text plus a nonce.')) {
          return fail();
        }
        final result = nonces.consume(nonce!, family: signed.family, address: signed.address);
        if (!check('Nonce', result == NonceCheck.ok, result.explanation)) return fail();

      case SignInLevel.standard:
        final m = SignInMessages.parseStandard(signed.message);
        if (!check(
          'Message',
          m != null,
          m != null ? 'It has every field of a level 3 message.' : 'Not a level 3 message.',
        )) {
          return fail();
        }
        if (!check(
          'Domain',
          m!.domain == identity.domain && m.uri == identity.uri,
          m.domain == identity.domain
              ? 'Signed for ${m.domain}, this app. A message signed on a phishing site would name that site.'
              : 'Signed for ${m.domain}, not ${identity.domain}. It may come from a phishing site.',
        )) {
          return fail();
        }
        final sameAccount = signed.family == ChainFamily.evm
            ? m.address.toLowerCase() == signed.address.toLowerCase()
            : m.address == signed.address;
        if (!check(
          'Account',
          sameAccount && m.family == signed.family,
          sameAccount ? 'The message names the account that signed it.' : 'The message names ${m.address}.',
        )) {
          return fail();
        }
        if (!check(
          'Chain',
          m.chainId == chainId,
          m.chainId == chainId
              ? 'Chain ID ${m.chainId}, the network you are on.'
              : 'Chain ID ${m.chainId}, not $chainId.',
        )) {
          return fail();
        }
        final now = _now();
        final timely = !m.issuedAt.isAfter(now.add(clockSkew)) && now.isBefore(m.expiresAt);
        if (!check(
          'Time',
          timely,
          timely
              ? 'Issued ${m.issuedAt.toUtc().toIso8601String()}, valid until ${m.expiresAt.toUtc().toIso8601String()}.'
              : 'Outside its validity window.',
        )) {
          return fail();
        }
        if (signed.family == ChainFamily.near) {
          // NEP-413 signs its own nonce field: it must be the server's nonce.
          final issued = nonces.find(m.nonce);
          final matches = issued != null && signed.nonce == _base64(issued.bytes);
          if (!check(
            'NEP-413 nonce',
            matches,
            matches ? 'The NEP-413 nonce is the server nonce.' : 'The NEP-413 nonce is not the server nonce.',
          )) {
            return fail();
          }
        }
        final result = nonces.consume(m.nonce, family: signed.family, address: signed.address);
        if (!check('Nonce', result == NonceCheck.ok, result.explanation)) return fail();
    }

    // 3. All good: a session.
    final issued = sessions.issue(family: signed.family, address: signed.address, chainId: chainId, level: level);
    check('Session', true, 'Issued a session token, valid until ${issued.session.expiresAt.toIso8601String()}.');
    return SignInResult(checks: checks, token: issued.token, session: issued.session);
  }

  Session session(String? token) =>
      (token == null ? null : sessions.read(token)) ?? (throw const UnauthorizedException());

  Description setDescription(String? token, String text) => descriptions.set(session(token), text);

  List<Description> listDescriptions() => descriptions.list();

  static String _base64(List<int> bytes) => base64Encode(bytes);
}
