import 'dart:convert';

import 'package:http/http.dart';

Future<String?> getSuiBalance(String rpcUrl, String walletAddress, [String? tokenAddress]) async {
  final response = await Client().post(
    Uri.parse(rpcUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'suix_getBalance',
      'params': [walletAddress, if (tokenAddress != null) tokenAddress],
    }),
  );

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data.containsKey('error')) throw Exception(data['error']['message']);

  final symbol = tokenAddress == null ? 'SUI' : '';
  final totalBalance = data['result']['totalBalance'] as String;
  return '${BigInt.parse(totalBalance) / BigInt.from(10).pow(9)} $symbol';
}

Future<List<(String hash, String from, DateTime timestamp)>> getLatestSuiTransactions(String rpcUrl) async {
  final List<(String, String, DateTime)> txs = [];
  final response = await Client().post(
    Uri.parse(rpcUrl),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'suix_queryTransactionBlocks',
      'params': [
        {
          'options': {'showInput': true},
        },
        null,
        10,
        true,
      ],
    }),
  );

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (!data.containsKey('error') && data['result'] != null) {
    final raws = data['result']['data'] as List?;
    if (raws != null) {
      for (var tx in raws) {
        final hash = tx['digest'] as String;
        final from = tx['transaction']['data']['sender'] as String;
        final timestampMillis = int.parse(tx['timestampMs']);
        final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMillis, isUtc: true);
        txs.add((hash, from, timestamp));
      }
    }
  }
  return txs;
}
