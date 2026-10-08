/// Reads the Move counter on Sui testnet through Sui's GraphQL API.
///
/// Sui stores the counter in one shared `Registry` object. Its `counters`
/// field is a `Table`, and each entry of a table is a "dynamic field" of the
/// table's ID, looked up by the BCS bytes of its key (here, an address).
library;

import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../counter_reader.dart';
import '../deployments.g.dart';

class SuiReader extends CounterReader {
  SuiReader(super.network, super.pool);

  String? _tableId;

  @override
  Future<int> totalUsers() async => int.parse((await _registry())['total_users'] as String);

  @override
  Future<UserCounter> userCounter(String address) async {
    final tableId = _tableId ?? ((await _registry())['counters'] as Map)['id'] as String;
    // The key's BCS encoding: an address is just its 32 bytes.
    final key = base64Encode(BytesUtils.fromHexString(_normalize(address)));
    final data = await pool.graphql(
      r'query($table: SuiAddress!, $key: Base64!) {'
      r'  address(address: $table) { dynamicField(name: { type: "address", bcs: $key }) {'
      r'    value { ... on MoveValue { json } } } } }',
      {'table': tableId, 'key': key},
    );
    final field = (data['address'] as Map?)?['dynamicField'] as Map?;
    if (field == null) return const UserCounter(value: 0, isUser: false);
    final json = (field['value'] as Map)['json'] as Map;
    return UserCounter(value: _signed(json['negative'] as bool, json['magnitude']), isUser: true);
  }

  @override
  Future<BigInt> balance(String address) async {
    final data = await pool.graphql(
      r'query($owner: SuiAddress!) { address(address: $owner) { balance(coinType: "0x2::sui::SUI") { totalBalance } } }',
      {'owner': _normalize(address)},
    );
    final total = ((data['address'] as Map?)?['balance'] as Map?)?['totalBalance'];
    return BigInt.parse((total ?? '0').toString());
  }

  @override
  Future<List<CounterActivity>> recentActivity({int limit = 8}) async {
    final data = await pool.graphql(
      r'query($type: String!, $last: Int!) {'
      r'  events(last: $last, filter: { type: $type }) {'
      r'    nodes { contents { json } timestamp transaction { digest } } } }',
      {'type': '${Deployments.suiPackageId}::counter::CounterChanged', 'last': limit},
    );
    final nodes = ((data['events'] as Map)['nodes'] as List).cast<Map<String, dynamic>>();
    // `last: n` returns the newest n in chronological order. Show newest first.
    return [
      for (final node in nodes.reversed)
        () {
          final json = (node['contents'] as Map)['json'] as Map;
          return CounterActivity(
            user: json['user'] as String,
            oldValue: _signed(json['old_negative'] as bool, json['old_magnitude']),
            newValue: _signed(json['new_negative'] as bool, json['new_magnitude']),
            action: CounterAction.fromIndex(json['action'] as int),
            txId: (node['transaction'] as Map)['digest'] as String,
            time: DateTime.tryParse(node['timestamp'] as String? ?? ''),
          );
        }(),
    ];
  }

  @override
  bool isValidAddress(String address) => RegExp(r'^0x[0-9a-fA-F]{1,64}$').hasMatch(address.trim());

  @override
  String get howTotalUsersIsRead =>
      'A GraphQL query for the shared Registry object, reading total_users from its JSON contents.';

  @override
  String get howActivityIsRead => 'A GraphQL query for the latest CounterChanged events emitted by the package.';

  @override
  Future<void> checkEndpoints() => pool.checkAll((endpoint, client) async {
    final response = await client.post(
      endpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'query': '{ chainIdentifier }'}),
    );
    if (((jsonDecode(response.body) as Map)['data'] as Map?)?['chainIdentifier'] == null) {
      throw StateError('no chain identifier');
    }
  });

  Future<Map<String, dynamic>> _registry() async {
    final data = await pool.graphql(
      r'query($id: SuiAddress!) { object(address: $id) { asMoveObject { contents { json } } } }',
      {'id': Deployments.suiRegistryId},
    );
    final json = (((data['object'] as Map)['asMoveObject'] as Map)['contents'] as Map)['json'] as Map<String, dynamic>;
    _tableId = (json['counters'] as Map)['id'] as String;
    return json;
  }

  /// Sui addresses are 32 bytes; short forms like 0x2 are left-padded.
  static String _normalize(String address) => '0x${address.trim().replaceFirst('0x', '').padLeft(64, '0')}';

  /// Move has no signed integers, so the contract stores sign + magnitude.
  static int _signed(bool negative, Object magnitude) {
    final value = int.parse(magnitude.toString());
    return negative ? -value : value;
  }
}
