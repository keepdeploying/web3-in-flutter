import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:test/test.dart';

import 'helpers/evm_signer.dart';

final address = testAddress;
SignedMessage sign(String message, {String? as}) => signEvm(message, as: as);

void main() {
  var now = DateTime.utc(2026, 10, 14, 12);
  late CounterServer server;
  setUp(() {
    now = DateTime.utc(2026, 10, 14, 12);
    server = CounterServer(clock: () => now);
  });

  ChallengeRequest request(SignInLevel level, {String chainId = '11155111'}) =>
      ChallengeRequest(level: level, family: ChainFamily.evm, address: address, chainId: chainId);

  Future<SignInResult> signIn(SignInLevel level, SignedMessage signed, {String chainId = '11155111'}) =>
      server.signIn(signed, level: level, chainId: chainId);

  group('level 1, fixed message', () {
    test('signs in, and a replayed signature signs in again', () async {
      final signed = sign(server.challenge(request(SignInLevel.fixed)).message);
      final first = await signIn(SignInLevel.fixed, signed);
      expect(first.ok, isTrue);
      expect(first.session!.address, address);
      // The weakness level 1 demonstrates: a copied signature works forever.
      now = now.add(const Duration(days: 365));
      expect((await signIn(SignInLevel.fixed, signed)).ok, isTrue);
    });

    test('rejects any other text', () async {
      final result = await signIn(SignInLevel.fixed, sign('Sign in to something else'));
      expect(result.ok, isFalse);
      expect(result.failure!.label, 'Message');
    });
  });

  group('level 2, nonce', () {
    test('signs in once, and the replay is refused', () async {
      final challenge = server.challenge(request(SignInLevel.nonce));
      expect(challenge.message, startsWith('${SignInMessages.fixedText}\n\nNonce: '));
      final signed = sign(challenge.message);
      expect((await signIn(SignInLevel.nonce, signed)).ok, isTrue);
      final replay = await signIn(SignInLevel.nonce, signed);
      expect(replay.ok, isFalse);
      expect(replay.failure!.label, 'Nonce');
      expect(replay.failure!.detail, NonceCheck.used.explanation);
    });

    test('refuses an expired nonce and a made-up one', () async {
      final signed = sign(server.challenge(request(SignInLevel.nonce)).message);
      now = now.add(const Duration(minutes: 6));
      expect((await signIn(SignInLevel.nonce, signed)).failure!.detail, NonceCheck.expired.explanation);
      final madeUp = await signIn(SignInLevel.nonce, sign(SignInMessages.withNonce('abc123')));
      expect(madeUp.failure!.detail, NonceCheck.unknown.explanation);
    });

    test('a bad signature does not burn the nonce', () async {
      final challenge = server.challenge(request(SignInLevel.nonce));
      final forged = SignedMessage(
        family: ChainFamily.evm,
        address: address,
        message: challenge.message,
        signature: '0x${'11' * 65}',
      );
      expect((await signIn(SignInLevel.nonce, forged)).failure!.label, 'Signature');
      expect((await signIn(SignInLevel.nonce, sign(challenge.message))).ok, isTrue);
    });
  });

  group('level 3, standard message', () {
    test('signs in with every field checked', () async {
      final challenge = server.challenge(request(SignInLevel.standard));
      expect(
        challenge.message,
        startsWith('flutter-counter.app wants you to sign in with your Ethereum account:\n$address\n'),
      );
      final result = await signIn(SignInLevel.standard, sign(challenge.message));
      expect(result.ok, isTrue, reason: result.failure?.detail);
      expect(result.checks.map((c) => c.label), [
        'Signature',
        'Message',
        'Domain',
        'Account',
        'Chain',
        'Time',
        'Nonce',
        'Session',
      ]);
    });

    test('refuses a replay', () async {
      final signed = sign(server.challenge(request(SignInLevel.standard)).message);
      expect((await signIn(SignInLevel.standard, signed)).ok, isTrue);
      expect((await signIn(SignInLevel.standard, signed)).failure!.label, 'Nonce');
    });

    test('refuses a message signed for another domain (phishing)', () async {
      final challenge = server.challenge(request(SignInLevel.standard));
      final phished = challenge.message.replaceFirst(
        'flutter-counter.app wants',
        'flutter-counter.app.evil.example wants',
      );
      final result = await signIn(SignInLevel.standard, sign(phished));
      expect(result.failure!.label, 'Domain');
    });

    test('refuses the wrong chain and an expired message', () async {
      final signed = sign(server.challenge(request(SignInLevel.standard)).message);
      expect((await signIn(SignInLevel.standard, signed, chainId: '84532')).failure!.label, 'Chain');
      now = now.add(const Duration(minutes: 10));
      expect((await signIn(SignInLevel.standard, signed)).failure!.label, 'Time');
    });

    test('the message parses back to what was built', () {
      final m = StandardMessage(
        domain: 'flutter-counter.app',
        family: ChainFamily.sui,
        address: '0xabc',
        statement: 'Sign in to Flutter Counter.',
        uri: 'https://flutter-counter.app',
        chainId: 'testnet',
        nonce: 'N0nce',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 1, 0, 5),
      );
      final parsed = SignInMessages.parseStandard(SignInMessages.standard(m))!;
      expect(
        [parsed.domain, parsed.family, parsed.address, parsed.chainId, parsed.nonce],
        [m.domain, m.family, m.address, m.chainId, m.nonce],
      );
      expect(parsed.expiresAt, m.expiresAt);
    });
  });

  group('sessions and descriptions', () {
    test('only a valid session can write a description', () async {
      final result = await signIn(SignInLevel.fixed, sign(SignInMessages.fixed()));
      server.setDescription(result.token, '  gm from Sepolia  ');
      expect(server.listDescriptions().single.text, 'gm from Sepolia');
      expect(() => server.setDescription(null, 'hi'), throwsA(isA<UnauthorizedException>()));
      expect(() => server.setDescription('${result.token}x', 'hi'), throwsA(isA<UnauthorizedException>()));
      expect(() => server.setDescription(result.token, 'x' * 141), throwsArgumentError);
    });

    test('tokens are tamper-proof and expire', () async {
      final result = await signIn(SignInLevel.fixed, sign(SignInMessages.fixed()));
      final parts = result.token!.split('.');
      final otherServer = CounterServer(clock: () => now);
      expect(otherServer.sessions.read(result.token!), isNull, reason: 'different secret');
      expect(server.sessions.read('${parts[0]}.${parts[1]}A.${parts[2]}'), isNull);
      expect(server.sessions.read(result.token!)!.address, address);
      now = now.add(const Duration(hours: 2));
      expect(server.sessions.read(result.token!), isNull);
    });
  });
}
