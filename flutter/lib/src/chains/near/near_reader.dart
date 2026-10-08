/// Reads the NEAR counter contract on testnet.
///
/// NEAR's RPC runs view functions directly (`call_function`), with JSON
/// arguments sent as base64. The RPC has no "history of an account", so
/// recent activity comes from FastNear's free transactions API, and the
/// counter's events from each transaction's logs.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../counter_reader.dart';

class NearReader extends CounterReader {
  NearReader(super.network, super.pool, {http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// FastNear's indexer for testnet transactions.
  static final txApi = Uri.parse('https://tx.test.fastnear.com');

  @override
  Future<int> totalUsers() async => await _view('total_users', {}) as int;

  @override
  Future<UserCounter> userCounter(String address) async {
    final args = {'account_id': address.trim()};
    final results = await Future.wait([_view('get_value', args), _view('is_user', args)]);
    return UserCounter(value: results[0] as int, isUser: results[1] as bool);
  }

  @override
  Future<BigInt> balance(String address) async {
    try {
      final result = await pool.jsonRpc('query', {
        'request_type': 'view_account',
        'finality': 'final',
        'account_id': address.trim(),
      }) as Map;
      return BigInt.parse(result['amount'] as String);
    } on Exception catch (e) {
      // An implicit account that never received funds doesn't exist yet.
      if (e.toString().toLowerCase().contains('does not exist') || e.toString().contains('UNKNOWN_ACCOUNT')) {
        return BigInt.zero;
      }
      rethrow;
    }
  }

  @override
  Future<List<CounterActivity>> recentActivity({int limit = 8}) async {
    final listing = await _post('/v0/account', {'account_id': network.counter});
    final hashes = [
      for (final tx in (listing['account_txs'] as List).cast<Map<String, dynamic>>())
        if (tx['is_function_call'] == true && tx['is_success'] == true) tx['transaction_hash'] as String,
    ].take(limit).toList();
    if (hashes.isEmpty) return [];

    final details = await _post('/v0/transactions', {'tx_hashes': hashes});
    final activity = <CounterActivity>[];
    for (final tx in (details['transactions'] as List).cast<Map<String, dynamic>>()) {
      final hash = (tx['transaction'] as Map)['hash'] as String;
      for (final receipt in (tx['receipts'] as List).cast<Map<String, dynamic>>()) {
        final outcome = (receipt['execution_outcome'] as Map)['outcome'] as Map;
        // The block timestamp is in nanoseconds.
        final nanos = int.tryParse('${(receipt['execution_outcome'] as Map)['block_timestamp'] ?? ''}');
        for (final log in (outcome['logs'] as List).cast<String>()) {
          // Contracts emit NEP-297 events as logs starting with EVENT_JSON:.
          if (!log.startsWith('EVENT_JSON:')) continue;
          final event = jsonDecode(log.substring(11)) as Map<String, dynamic>;
          if (event['standard'] != 'flutter_counter' || event['event'] != 'counter_changed') continue;
          final raw = event['data'];
          final data = (raw is List ? raw.first : raw) as Map<String, dynamic>;
          activity.add(
            CounterActivity(
              user: data['user'] as String,
              oldValue: data['old_value'] as int,
              newValue: data['new_value'] as int,
              action: CounterAction.fromName(data['action'] as String),
              txId: hash,
              time: nanos == null ? null : DateTime.fromMicrosecondsSinceEpoch(nanos ~/ 1000),
            ),
          );
        }
      }
    }
    // Keep the order of the listing (newest first).
    activity.sort((a, b) => hashes.indexOf(a.txId).compareTo(hashes.indexOf(b.txId)));
    return activity;
  }

  @override
  bool isValidAddress(String address) {
    final a = address.trim();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(a) ||
        RegExp(r'^(([a-z\d]+[\-_])*[a-z\d]+\.)*([a-z\d]+[\-_])*[a-z\d]+$').hasMatch(a) && a.length >= 2;
  }

  @override
  String get howTotalUsersIsRead =>
      'A "query" RPC with request_type call_function: the view method total_users, run by the node for free.';

  @override
  String get howActivityIsRead =>
      "FastNear's transaction API lists the contract's transactions, then their logs give the EVENT_JSON events.";

  @override
  Future<void> checkEndpoints() => pool.checkAll((endpoint, client) async {
    final response = await client.post(
      endpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'block',
        'params': {'finality': 'final'},
      }),
    );
    if ((jsonDecode(response.body) as Map)['result'] == null) throw StateError('no block');
  });

  /// Runs a view method and decodes its JSON result, which NEAR returns as
  /// an array of bytes.
  Future<Object?> _view(String method, Map<String, dynamic> args) async {
    final result = await pool.jsonRpc('query', {
      'request_type': 'call_function',
      'finality': 'final',
      'account_id': network.counter,
      'method_name': method,
      'args_base64': base64Encode(utf8.encode(jsonEncode(args))),
    }) as Map;
    return jsonDecode(utf8.decode((result['result'] as List).cast<int>()));
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          txApi.replace(path: path),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
