/// A list of free RPC endpoints for one network that behaves like one
/// reliable endpoint.
///
/// Free public endpoints come and go: they rate-limit, time out, or shut
/// down without notice. Two did during this project (Sepolia on dRPC and
/// Polygon's own Amoy RPC). The pool tries endpoints in order of preference,
/// puts failing ones on a growing cooldown, and goes back to the preferred
/// one once its cooldown ends.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// An error from an endpoint or from the chain.
///
/// [switchEndpoint] says whether another endpoint might succeed. Network
/// failures, rate limits and server errors switch. Errors that are the app's
/// fault (a reverted call, bad parameters, a nonce problem) don't: retrying
/// them elsewhere gives the same answer, or worse, sends a transaction twice.
class RpcException implements Exception {
  RpcException(this.message, {this.code, this.switchEndpoint = true});

  final String message;
  final int? code;
  final bool switchEndpoint;

  @override
  String toString() => code == null ? message : '$message (code $code)';
}

/// What the pool knows about one endpoint.
class EndpointStatus {
  EndpointStatus(this.url);

  final String url;
  Duration? lastLatency;
  String? lastError;
  DateTime? lastSuccess;
  int consecutiveFailures = 0;
  DateTime? cooldownUntil;

  String get host => Uri.parse(url).host;

  bool isCoolingDown(DateTime now) => cooldownUntil != null && now.isBefore(cooldownUntil!);
}

/// One line in the pool's switch log, shown on the Network status screen.
class PoolEvent {
  PoolEvent(this.time, this.message);
  final DateTime time;
  final String message;
}

class RpcPool {
  RpcPool({required List<String> urls, http.Client? client, this.timeout = const Duration(seconds: 8)})
    : assert(urls.isNotEmpty),
      endpoints = [for (final url in urls) EndpointStatus(url)],
      _client = client ?? http.Client();

  final List<EndpointStatus> endpoints;
  final Duration timeout;
  final http.Client _client;
  final List<PoolEvent> log = [];

  final _changes = StreamController<void>.broadcast();

  /// Fires whenever an endpoint's status changes, so the Network status
  /// screen can redraw. (A plain Dart stream keeps this file free of
  /// Flutter, so command-line tools and tests can use it too.)
  Stream<void> get changes => _changes.stream;

  /// The endpoint that answered the last successful request.
  EndpointStatus? lastUsed;

  /// How long to rest an endpoint after 1, 2, 3 and 4+ failures in a row.
  static const cooldowns = [Duration(seconds: 60), Duration(minutes: 2), Duration(minutes: 5), Duration(minutes: 10)];

  /// The endpoint the next request will try first.
  EndpointStatus get active {
    final now = DateTime.now();
    return endpoints.firstWhere((e) => !e.isCoolingDown(now), orElse: () => _soonestAvailable());
  }

  EndpointStatus _soonestAvailable() => endpoints.reduce((a, b) => a.cooldownUntil!.isBefore(b.cooldownUntil!) ? a : b);

  /// Runs [call] against each endpoint in turn until one succeeds.
  ///
  /// Endpoints resting after recent failures are tried last, so a request
  /// still succeeds if every endpoint has failed recently.
  Future<T> request<T>(Future<T> Function(Uri endpoint, http.Client client) call, {Duration? timeout}) async {
    final now = DateTime.now();
    final order = [...endpoints.where((e) => !e.isCoolingDown(now)), ...endpoints.where((e) => e.isCoolingDown(now))];

    Object? lastError;
    for (final endpoint in order) {
      final watch = Stopwatch()..start();
      try {
        final result = await call(Uri.parse(endpoint.url), _client).timeout(timeout ?? this.timeout);
        _succeeded(endpoint, watch.elapsed);
        return result;
      } on RpcException catch (e) {
        if (!e.switchEndpoint) {
          // The endpoint worked; the request itself was wrong.
          _succeeded(endpoint, watch.elapsed);
          rethrow;
        }
        lastError = e;
        _failed(endpoint, e.toString());
      } on TimeoutException {
        lastError = RpcException('Timed out after ${(timeout ?? this.timeout).inSeconds}s');
        _failed(endpoint, 'timed out');
      } catch (e) {
        // Socket errors, TLS errors, CORS blocks on the web, invalid JSON.
        lastError = e;
        _failed(endpoint, e.toString());
      }
    }
    throw lastError ?? RpcException('No endpoint answered');
  }

  /// Sends one JSON-RPC 2.0 request (EVM, Solana, NEAR) and returns `result`.
  Future<dynamic> jsonRpc(String method, [Object? params]) {
    return request((endpoint, client) async {
      final body = jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': ?params});
      final response = await client.post(endpoint, headers: {'content-type': 'application/json'}, body: body);
      final json = _decode(response);
      final error = json['error'];
      if (error != null) throw _rpcError(error);
      return json['result'];
    });
  }

  /// Sends a GraphQL query (Sui) and returns `data`.
  Future<Map<String, dynamic>> graphql(String query, [Map<String, dynamic>? variables]) {
    return request((endpoint, client) async {
      final body = jsonEncode({'query': query, 'variables': ?variables});
      final response = await client.post(endpoint, headers: {'content-type': 'application/json'}, body: body);
      final json = _decode(response);
      final errors = json['errors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        throw RpcException((errors.first as Map)['message'].toString(), switchEndpoint: false);
      }
      return json['data'] as Map<String, dynamic>;
    });
  }

  /// Sends a GET to a REST path (Cosmos LCD) and returns the JSON body.
  Future<Map<String, dynamic>> getJson(String path, [Map<String, String>? query]) {
    return request((endpoint, client) async {
      final uri = endpoint.replace(path: '${endpoint.path}$path', queryParameters: query);
      return _decode(await client.get(uri));
    });
  }

  /// Asks every endpoint one cheap question and records how each did.
  /// [probe] runs against a single endpoint; throw to mark it unhealthy.
  Future<void> checkAll(Future<void> Function(Uri endpoint, http.Client client) probe) async {
    await Future.wait([
      for (final endpoint in endpoints)
        () async {
          final watch = Stopwatch()..start();
          try {
            await probe(Uri.parse(endpoint.url), _client).timeout(timeout);
            _succeeded(endpoint, watch.elapsed, quiet: true);
          } catch (e) {
            _failed(endpoint, e is TimeoutException ? 'timed out' : e.toString());
          }
        }(),
    ]);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final status = response.statusCode;
    if (status == 429) throw RpcException('Rate limited (HTTP 429)');
    if (status >= 500) throw RpcException('Server error (HTTP $status)');
    if (status == 403 || status == 404 || status == 410) throw RpcException('Unavailable (HTTP $status)');
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      // Often an HTML page from a proxy or a "service moved" notice.
      throw RpcException('Not a JSON response (HTTP $status)');
    }
  }

  RpcException _rpcError(Object error) {
    final map = error is Map ? error : {'message': error.toString()};
    final code = map['code'] is int ? map['code'] as int : null;
    final message = (map['message'] ?? map['name'] ?? 'RPC error').toString();
    // NEAR puts the real reason in `cause` or `data`, so look at the whole error.
    final lower = jsonEncode(map).toLowerCase();
    // The app's fault: retrying on another endpoint won't help.
    final appError =
        code == 3 ||
        code == -32602 ||
        lower.contains('revert') ||
        lower.contains('nonce') ||
        lower.contains('insufficient funds') ||
        lower.contains('unknown_account') ||
        lower.contains('does not exist');
    return RpcException(message, code: code, switchEndpoint: !appError);
  }

  void _succeeded(EndpointStatus endpoint, Duration latency, {bool quiet = false}) {
    final previous = lastUsed;
    endpoint
      ..lastLatency = latency
      ..lastSuccess = DateTime.now()
      ..lastError = null
      ..consecutiveFailures = 0
      ..cooldownUntil = null;
    if (!quiet) {
      if (previous != null && previous != endpoint) _record('Now using ${endpoint.host}');
      lastUsed = endpoint;
    }
    _changes.add(null);
  }

  void _failed(EndpointStatus endpoint, String reason) {
    endpoint.consecutiveFailures++;
    final rest = cooldowns[(endpoint.consecutiveFailures - 1).clamp(0, cooldowns.length - 1)];
    endpoint
      ..lastError = reason
      ..cooldownUntil = DateTime.now().add(rest);
    _record(
      '${endpoint.host} failed ($reason). Resting it for ${rest.inMinutes > 0 ? '${rest.inMinutes} min' : '${rest.inSeconds} s'}.',
    );
    _changes.add(null);
  }

  void _record(String message) {
    log.insert(0, PoolEvent(DateTime.now(), message));
    if (log.length > 50) log.removeLast();
  }

  void dispose() {
    _client.close();
    _changes.close();
  }
}
