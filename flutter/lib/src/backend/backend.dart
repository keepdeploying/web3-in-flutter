import 'dart:convert';

import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' as lib show health;
import 'package:http/http.dart' as http;

export 'package:flutter_counter_server/flutter_counter_server.dart'
    show Challenge, ChallengeRequest, Check, Description, Session, SignInLevel, SignInResult, UnauthorizedException;

/// Everything the app asks of its backend. The two implementations give the
/// same answers, so the UI never knows which one it talks to.
abstract class Backend {
  /// For the UI: where the checks run.
  String get description;

  Future<Map<String, Object?>> health();
  Future<Challenge> challenge(ChallengeRequest request);
  Future<SignInResult> signIn(SignedMessage signed, {required SignInLevel level, required String chainId});
  Future<Description> setDescription(String token, String text);
  Future<List<Description>> descriptions();
}

/// Runs the server's Dart code inside the app.
///
/// Handy for the web demo and the workshop: nothing to deploy. But it is a
/// simulation: a real app must verify signatures on a server it controls,
/// because anything running on the user's device can be changed by them.
class LocalBackend implements Backend {
  LocalBackend({CounterServer? server})
    : server = server ?? CounterServer(verifier: SignatureVerifier(lookup: RpcChainLookup()));

  final CounterServer server;

  @override
  String get description => 'in the app (simulated)';

  @override
  Future<Map<String, Object?>> health() async => lib.health(mode: 'local');

  @override
  Future<Challenge> challenge(ChallengeRequest request) async => server.challenge(request);

  @override
  Future<SignInResult> signIn(SignedMessage signed, {required SignInLevel level, required String chainId}) =>
      server.signIn(signed, level: level, chainId: chainId);

  @override
  Future<Description> setDescription(String token, String text) async => server.setDescription(token, text);

  @override
  Future<List<Description>> descriptions() async => server.listDescriptions();
}

/// Talks to `server/bin/server.dart` over HTTP.
class HttpBackend implements Backend {
  HttpBackend(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  @override
  String get description => 'on the server at ${baseUrl.host}:${baseUrl.port}';

  @override
  Future<Map<String, Object?>> health() async => await _send('GET', '/health') as Map<String, Object?>;

  @override
  Future<Challenge> challenge(ChallengeRequest request) async =>
      Challenge.fromJson(await _send('POST', '/auth/challenge', body: request.toJson()) as Map<String, dynamic>);

  @override
  Future<SignInResult> signIn(SignedMessage signed, {required SignInLevel level, required String chainId}) async =>
      SignInResult.fromJson(
        await _send('POST', '/auth/sign-in', body: {'signed': signed.toJson(), 'level': level.name, 'chainId': chainId})
            as Map<String, dynamic>,
      );

  @override
  Future<Description> setDescription(String token, String text) async => Description.fromJson(
    await _send('PUT', '/me/description', body: {'text': text}, token: token) as Map<String, dynamic>,
  );

  @override
  Future<List<Description>> descriptions() async => [
    for (final d in await _send('GET', '/descriptions') as List) Description.fromJson(d as Map<String, dynamic>),
  ];

  Future<Object?> _send(String method, String path, {Object? body, String? token}) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..body = body == null ? '' : jsonEncode(body);
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    final response = await http.Response.fromStream(await _client.send(request));
    final json = response.body.isEmpty ? null : jsonDecode(response.body);
    final error = json is Map ? json['error'] as String? : null;
    return switch (response.statusCode) {
      200 => json,
      401 => throw UnauthorizedException(error ?? 'Sign in first.'),
      400 => throw ArgumentError(error ?? 'Bad request'),
      final status => throw Exception('Server error (HTTP $status)${error == null ? '' : ': $error'}'),
    };
  }
}
