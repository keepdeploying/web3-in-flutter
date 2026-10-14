import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_counter_server/http.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Runs the backend over HTTP:
///
///   cd server && dart run bin/server.dart
///
/// Settings, all optional, from environment variables:
/// - PORT: default 8080.
/// - SESSION_SECRET: hex key for session tokens. Without it a random key is
///   made at start, so restarting signs everyone out.
/// - APP_DOMAIN and APP_URI: what level 3 messages must name. Defaults to
///   flutter-counter.app.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final secret = env['SESSION_SECRET'];
  final identity = AppIdentity(
    domain: env['APP_DOMAIN'] ?? const AppIdentity().domain,
    uri: env['APP_URI'] ?? const AppIdentity().uri,
  );

  final server = CounterServer(
    identity: identity,
    sessionSecret: secret == null ? null : BytesUtils.fromHexString(secret),
    // A real server asks the chains about contract wallets, NEAR keys and
    // zkLogin.
    verifier: SignatureVerifier(lookup: RpcChainLookup(), nearRecipient: identity.domain),
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(counterRoutes(server));

  final http = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Flutter Counter server listening on http://localhost:${http.port}');
}

/// Flutter web runs on another port in development, so the server must
/// answer CORS preflight requests.
Middleware _cors() {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'access-control-allow-headers': 'content-type, authorization',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') return Response.ok('', headers: headers);
    final response = await inner(request);
    return response.change(headers: headers);
  };
}
