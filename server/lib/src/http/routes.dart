import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/counter_server.dart';
import '../auth/sign_in_messages.dart';
import '../health.dart';
import '../signing/signed_message.dart';

/// The HTTP API around [CounterServer]. Every route is a thin translation:
/// JSON in, call the server, JSON out.
///
/// | Route | Body | Answer |
/// | --- | --- | --- |
/// | GET /health | | `{ok, service, mode}` |
/// | POST /auth/challenge | ChallengeRequest | Challenge |
/// | POST /auth/sign-in | `{signed, level, chainId}` | SignInResult (always 200: the checks explain a refusal) |
/// | GET /me | `Authorization: Bearer <token>` | Session |
/// | PUT /me/description | `{text}`, with the token | Description |
/// | GET /descriptions | | `[Description]`, newest first |
Handler counterRoutes(CounterServer server) {
  final router = Router()
    ..get('/health', (Request _) => _json(health(mode: 'http')))
    ..post('/auth/challenge', (Request request) async {
      final body = await _body(request);
      return _json(server.challenge(ChallengeRequest.fromJson(body)).toJson());
    })
    ..post('/auth/sign-in', (Request request) async {
      final body = await _body(request);
      final result = await server.signIn(
        SignedMessage.fromJson(body['signed'] as Map<String, dynamic>),
        level: SignInLevel.values.byName(body['level'] as String),
        chainId: body['chainId'] as String,
      );
      return _json(result.toJson());
    })
    ..get('/me', (Request request) => _json(server.session(_token(request)).toJson()))
    ..put('/me/description', (Request request) async {
      final body = await _body(request);
      return _json(server.setDescription(_token(request), body['text'] as String? ?? '').toJson());
    })
    ..get('/descriptions', (Request _) => _json([for (final d in server.listDescriptions()) d.toJson()]));

  return const Pipeline().addMiddleware(_errors()).addHandler(router.call);
}

String? _token(Request request) {
  final header = request.headers['authorization'] ?? '';
  return header.startsWith('Bearer ') ? header.substring(7) : null;
}

Future<Map<String, dynamic>> _body(Request request) async =>
    jsonDecode(await request.readAsString()) as Map<String, dynamic>;

Response _json(Object body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json'});

/// Turns exceptions into JSON errors: 401 without a valid session, 400 for
/// bad input, 500 for anything else.
Middleware _errors() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on UnauthorizedException catch (e) {
        return _json({'error': e.message}, status: 401);
      } on ArgumentError catch (e) {
        return _json({'error': '${e.message}'}, status: 400);
      } on FormatException catch (e) {
        return _json({'error': 'Bad request: ${e.message}'}, status: 400);
      } on TypeError {
        return _json({'error': 'Bad request: missing or wrong fields'}, status: 400);
      }
    };
