/// Reads the Solidity counter on any EVM network, with plain JSON-RPC.
///
/// No EVM library needed for reads: a call is just the 4-byte function
/// selector plus ABI-encoded arguments, sent with `eth_call`, and events are
/// logs filtered by the contract address and the event's topic.
library;

import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../counter_reader.dart';
import '../deployments.g.dart';

class EvmReader extends CounterReader {
  EvmReader(super.network, super.pool);

  /// The first 4 bytes of keccak256 of the function signature.
  static String selector(String signature) =>
      BytesUtils.toHexString(QuickCrypto.keccack256Hash(utf8.encode(signature)).sublist(0, 4), prefix: '0x');

  /// The full keccak256 of the event signature: the log's first topic.
  static final counterChangedTopic = BytesUtils.toHexString(
    QuickCrypto.keccack256Hash(utf8.encode('CounterChanged(address,int256,int256,uint8)')),
    prefix: '0x',
  );

  /// How many blocks one `eth_getLogs` request covers. Every endpoint in
  /// the lists accepts 10,000.
  static const logSpan = 10000;

  /// How far back to look for activity, in requests of [logSpan] blocks.
  static const maxLogRequests = 6;

  @override
  Future<int> totalUsers() async => _decodeInt(await _call(selector('totalUsers()'))).toInt();

  @override
  Future<UserCounter> userCounter(String address) async {
    final arg = _encodeAddress(address);
    final results = await Future.wait([
      _call('${selector('counterOf(address)')}$arg'),
      _call('${selector('isUser(address)')}$arg'),
    ]);
    return UserCounter(
      value: _decodeInt(results[0], signed: true).toInt(),
      isUser: _decodeInt(results[1]) == BigInt.one,
    );
  }

  @override
  Future<BigInt> balance(String address) async {
    final hex = await pool.jsonRpc('eth_getBalance', [address, 'latest']) as String;
    return _decodeInt(hex);
  }

  @override
  Future<List<CounterActivity>> recentActivity({int limit = 8}) async {
    final latest = _decodeInt(await pool.jsonRpc('eth_blockNumber') as String).toInt();
    final deployBlock = Deployments.evmDeployBlocks[int.parse(network.chainId)] ?? 0;

    // Walk back from the newest block in chunks until there are enough logs.
    final logs = <Map<String, dynamic>>[];
    var to = latest;
    for (var i = 0; i < maxLogRequests && to >= deployBlock && logs.length < limit; i++) {
      final from = (to - logSpan + 1).clamp(deployBlock, to);
      final chunk = await pool.jsonRpc('eth_getLogs', [
        {
          'address': network.counter,
          'topics': [counterChangedTopic],
          'fromBlock': '0x${from.toRadixString(16)}',
          'toBlock': '0x${to.toRadixString(16)}',
        },
      ]) as List;
      logs.insertAll(0, chunk.cast<Map<String, dynamic>>());
      to = from - 1;
    }

    final newest = logs.reversed.take(limit).toList();
    // Logs carry block numbers, not times. Fetch each block's timestamp once.
    final blocks = {for (final log in newest) log['blockNumber'] as String};
    final times = <String, DateTime>{};
    await Future.wait([
      for (final block in blocks)
        pool.jsonRpc('eth_getBlockByNumber', [block, false]).then((b) {
          final seconds = _decodeInt((b as Map)['timestamp'] as String).toInt();
          times[block] = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        }),
    ]);

    return [
      for (final log in newest)
        () {
          // topics[1] is the indexed `user`, left-padded to 32 bytes.
          final user = checksumAddress((log['topics'] as List)[1].toString().substring(26));
          // data holds the non-indexed fields, 32 bytes each:
          // oldValue (int256), newValue (int256), action (uint8).
          final data = (log['data'] as String).substring(2);
          String word(int i) => data.substring(i * 64, (i + 1) * 64);
          return CounterActivity(
            user: user,
            oldValue: _decodeInt(word(0), signed: true).toInt(),
            newValue: _decodeInt(word(1), signed: true).toInt(),
            action: CounterAction.fromIndex(_decodeInt(word(2)).toInt()),
            txId: log['transactionHash'] as String,
            time: times[log['blockNumber']],
          );
        }(),
    ];
  }

  @override
  bool isValidAddress(String address) => RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address.trim());

  @override
  String get howTotalUsersIsRead =>
      'eth_call to totalUsers() (selector ${selector('totalUsers()')}) on the counter. Reads are free: no wallet, no gas.';

  @override
  String get howActivityIsRead =>
      'eth_getLogs for CounterChanged events from the counter, $logSpan blocks per request, newest first.';

  @override
  Future<void> checkEndpoints() => pool.checkAll((endpoint, client) async {
    final response = await client.post(
      endpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'eth_chainId', 'params': []}),
    );
    final id = (jsonDecode(response.body) as Map)['result'] as String;
    if (int.parse(id.substring(2), radix: 16).toString() != network.chainId) {
      throw StateError('wrong chain $id');
    }
  });

  /// Mixed-case EIP-55 form of an address, as wallets and explorers show it.
  ///
  /// Each hex letter is uppercased when the matching hex digit of the
  /// keccak256 of the lowercase address is 8 or more. The casing works as a
  /// checksum: a typo almost always breaks it.
  static String checksumAddress(String address) {
    final lower = address.toLowerCase().replaceFirst('0x', '');
    final hash = BytesUtils.toHexString(QuickCrypto.keccack256Hash(utf8.encode(lower)));
    return '0x${[for (var i = 0; i < 40; i++) int.parse(hash[i], radix: 16) >= 8 ? lower[i].toUpperCase() : lower[i]].join()}';
  }

  Future<String> _call(String data) async {
    return await pool.jsonRpc('eth_call', [
      {'to': network.counter, 'data': data},
      'latest',
    ]) as String;
  }

  /// ABI-encodes an address: 20 bytes, left-padded with zeros to 32.
  static String _encodeAddress(String address) => address.toLowerCase().replaceFirst('0x', '').padLeft(64, '0');

  /// Reads a 32-byte ABI word. Signed values use two's complement, so a
  /// word with the top bit set is negative.
  static BigInt _decodeInt(String hex, {bool signed = false}) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) return BigInt.zero;
    final value = BigInt.parse(clean, radix: 16);
    if (signed && clean.length == 64 && (value >> 255) == BigInt.one) return value - (BigInt.one << 256);
    return value;
  }
}
