/// Reads the CosmWasm counter on the Osmosis testnet, through the chain's
/// REST API (the "LCD").
///
/// CosmWasm contracts answer "smart queries": a JSON message, sent
/// base64-encoded in the URL. Changes show up as events on transactions,
/// which the LCD can search by contract address.
library;

import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../counter_reader.dart';

class OsmosisReader extends CounterReader {
  OsmosisReader(super.network, super.pool);

  @override
  Future<int> totalUsers() async {
    final result = await _smartQuery({'total_users': {}});
    return result['total_users'] as int;
  }

  @override
  Future<UserCounter> userCounter(String address) async {
    final result = await _smartQuery({
      'value': {'user': address.trim()},
    });
    return UserCounter(value: result['value'] as int, isUser: result['is_user'] as bool);
  }

  @override
  Future<BigInt> balance(String address) async {
    final json = await pool.getJson('/cosmos/bank/v1beta1/balances/${address.trim()}/by_denom', {'denom': 'uosmo'});
    return BigInt.parse(((json['balance'] as Map?)?['amount'] ?? '0').toString());
  }

  @override
  Future<List<CounterActivity>> recentActivity({int limit = 8}) async {
    final json = await pool.getJson('/cosmos/tx/v1beta1/txs', {
      'query': "execute._contract_address='${network.counter}'",
      'order_by': 'ORDER_BY_DESC',
      'pagination.limit': '$limit',
    });
    final activity = <CounterActivity>[];
    for (final tx in (json['tx_responses'] as List? ?? []).cast<Map<String, dynamic>>()) {
      for (final event in (tx['events'] as List).cast<Map<String, dynamic>>()) {
        // The contract's own events get a "wasm-" prefix.
        if (event['type'] != 'wasm-counter_changed') continue;
        final attributes = {
          for (final a in (event['attributes'] as List).cast<Map<String, dynamic>>()) a['key']: a['value'],
        };
        activity.add(
          CounterActivity(
            user: attributes['user'] as String,
            oldValue: int.parse(attributes['old_value'] as String),
            newValue: int.parse(attributes['new_value'] as String),
            action: CounterAction.fromName(attributes['action'] as String),
            txId: tx['txhash'] as String,
            time: DateTime.tryParse(tx['timestamp'] as String? ?? ''),
          ),
        );
      }
    }
    return activity;
  }

  @override
  bool isValidAddress(String address) {
    try {
      Bech32Decoder.decode('osmo', address.trim());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  String get howTotalUsersIsRead =>
      'A CosmWasm smart query {"total_users":{}}, base64-encoded in a GET to the REST API. Free, no wallet.';

  @override
  String get howActivityIsRead =>
      "A transaction search on the REST API for execute._contract_address='...', reading the counter_changed events.";

  @override
  Future<void> checkEndpoints() => pool.checkAll((endpoint, client) async {
    final response = await client.get(endpoint.replace(path: '/cosmos/base/tendermint/v1beta1/node_info'));
    final network = ((jsonDecode(response.body) as Map)['default_node_info'] as Map)['network'];
    if (network != this.network.chainId) throw StateError('wrong chain $network');
  });

  Future<Map<String, dynamic>> _smartQuery(Map<String, dynamic> query) {
    final encoded = base64Encode(utf8.encode(jsonEncode(query)));
    return pool
        .getJson('/cosmwasm/wasm/v1/contract/${network.counter}/smart/${Uri.encodeComponent(encoded)}')
        .then((json) => json['data'] as Map<String, dynamic>);
  }
}
