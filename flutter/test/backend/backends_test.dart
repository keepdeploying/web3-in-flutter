import 'dart:convert';

import 'package:flutter_counter/src/backend/backend.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' show CounterServer, SignatureVerifier;
import 'package:flutter_counter_server/http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart' as shelf;

const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

/// An HTTP client that hands requests straight to the server's routes, so
/// HttpBackend is tested against the real HTTP layer without a socket.
http.Client routesClient(CounterServer server) {
  final handler = counterRoutes(server);
  return MockClient((request) async {
    final response = await handler(
      shelf.Request(request.method, request.url, body: request.body, headers: request.headers),
    );
    return http.Response(await response.readAsString(), response.statusCode, headers: response.headers);
  });
}

void main() {
  final signer = InAppSigner(HdKeys.deriveAll(devPhrase)[ChainFamily.solana]!);
  final network = Networks.solanaDevnet;

  final backends = <String, Backend Function()>{
    'LocalBackend': () => LocalBackend(server: CounterServer(verifier: SignatureVerifier())),
    'HttpBackend': () => HttpBackend(
      Uri.parse('http://localhost:8080'),
      client: routesClient(CounterServer(verifier: SignatureVerifier())),
    ),
  };

  for (final MapEntry(key: name, value: make) in backends.entries) {
    test('$name: signs in, refuses the replay, saves a description', () async {
      final backend = make();
      expect((await backend.health())['ok'], isTrue);

      final challenge = await backend.challenge(
        ChallengeRequest(
          level: SignInLevel.standard,
          family: network.family,
          address: signer.address,
          chainId: network.chainId,
        ),
      );
      final signed = await signer.signMessage(challenge.message);
      final result = await backend.signIn(signed, level: SignInLevel.standard, chainId: network.chainId);
      expect(result.ok, isTrue, reason: result.failure?.detail);
      expect(result.checks.last.label, 'Session');

      final replay = await backend.signIn(signed, level: SignInLevel.standard, chainId: network.chainId);
      expect(replay.failure!.label, 'Nonce');

      await backend.setDescription(result.token!, 'gm from Solana');
      expect((await backend.descriptions()).single.text, 'gm from Solana');
      await expectLater(backend.setDescription('bad token', 'hi'), throwsA(isA<UnauthorizedException>()));
      await expectLater(backend.setDescription(result.token!, ''), throwsArgumentError);
    });
  }

  test('HttpBackend reports server errors with the status', () async {
    final backend = HttpBackend(
      Uri.parse('http://localhost:8080'),
      client: MockClient((_) async => http.Response(jsonEncode({'error': 'boom'}), 500)),
    );
    await expectLater(
      backend.descriptions(),
      throwsA(predicate((e) => '$e'.contains('HTTP 500') && '$e'.contains('boom'))),
    );
  });
}
