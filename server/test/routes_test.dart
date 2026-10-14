import 'dart:convert';

import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_counter_server/http.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'helpers/evm_signer.dart';

void main() {
  late Handler handler;
  setUp(() => handler = counterRoutes(CounterServer()));

  Future<(int, dynamic)> call(String method, String path, {Object? body, String? token}) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : (body is String ? body : jsonEncode(body)),
        headers: {'content-type': 'application/json', 'authorization': ?(token == null ? null : 'Bearer $token')},
      ),
    );
    final text = await response.readAsString();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  test('health', () async {
    final (status, body) = await call('GET', '/health');
    expect(status, 200);
    expect(body['mode'], 'http');
  });

  test('the whole flow: challenge, sign in, write a description, list', () async {
    final (_, challenge) = await call(
      'POST',
      '/auth/challenge',
      body: ChallengeRequest(
        level: SignInLevel.standard,
        family: ChainFamily.evm,
        address: testAddress,
        chainId: '11155111',
      ).toJson(),
    );
    final signed = signEvm(Challenge.fromJson(challenge as Map<String, dynamic>).message);
    final (status, result) = await call(
      'POST',
      '/auth/sign-in',
      body: {'signed': signed.toJson(), 'level': 'standard', 'chainId': '11155111'},
    );
    expect(status, 200);
    final signIn = SignInResult.fromJson(result as Map<String, dynamic>);
    expect(signIn.ok, isTrue, reason: signIn.failure?.detail);

    final (meStatus, me) = await call('GET', '/me', token: signIn.token);
    expect(meStatus, 200);
    expect(me['sub'], testAddress);

    final (putStatus, description) = await call('PUT', '/me/description', body: {'text': 'gm'}, token: signIn.token);
    expect(putStatus, 200);
    expect(description['text'], 'gm');
    final (_, list) = await call('GET', '/descriptions');
    expect((list as List).single['address'], testAddress);

    // The replay comes back as a refusal, with the checks explaining why.
    final (replayStatus, replay) = await call(
      'POST',
      '/auth/sign-in',
      body: {'signed': signed.toJson(), 'level': 'standard', 'chainId': '11155111'},
    );
    expect(replayStatus, 200);
    expect(SignInResult.fromJson(replay as Map<String, dynamic>).failure!.label, 'Nonce');
  });

  test('401 without a session, 400 for bad input', () async {
    expect((await call('GET', '/me')).$1, 401);
    expect((await call('PUT', '/me/description', body: {'text': 'hi'}, token: 'nope')).$1, 401);
    expect((await call('POST', '/auth/challenge', body: '{not json')).$1, 400);
    expect((await call('POST', '/auth/challenge', body: {'level': 'standard'})).$1, 400);
  });
}
