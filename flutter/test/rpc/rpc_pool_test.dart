import 'dart:convert';

import 'package:flutter_counter/src/rpc/rpc_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake set of endpoints. Each host answers with its own handler.
MockClient fake(Map<String, http.Response Function()> byHost, List<String> calls) {
  return MockClient((request) async {
    calls.add(request.url.host);
    return byHost[request.url.host]!();
  });
}

http.Response ok(Object result) => http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);
http.Response rpcError(int code, String message) => http.Response(
  jsonEncode({
    'jsonrpc': '2.0',
    'id': 1,
    'error': {'code': code, 'message': message},
  }),
  200,
);

void main() {
  const urls = ['https://a.test', 'https://b.test', 'https://c.test'];

  test('uses the first endpoint when it works', () async {
    final calls = <String>[];
    final pool = RpcPool(urls: urls, client: fake({'a.test': () => ok('0x1')}, calls));
    expect(await pool.jsonRpc('eth_chainId'), '0x1');
    expect(calls, ['a.test']);
    expect(pool.lastUsed!.host, 'a.test');
  });

  test('switches to the next endpoint on rate limits, server errors and HTML', () async {
    final calls = <String>[];
    final pool = RpcPool(
      urls: urls,
      client: fake({
        'a.test': () => http.Response('Too many requests', 429),
        'b.test': () => http.Response('<html>Bad gateway</html>', 200),
        'c.test': () => ok('0x2'),
      }, calls),
    );
    expect(await pool.jsonRpc('eth_blockNumber'), '0x2');
    expect(calls, ['a.test', 'b.test', 'c.test']);
    expect(pool.endpoints[0].cooldownUntil, isNotNull);
    expect(pool.log, isNotEmpty);
  });

  test('rests failed endpoints and tries them last next time', () async {
    final calls = <String>[];
    var aFails = true;
    final pool = RpcPool(
      urls: urls,
      client: fake({
        'a.test': () => aFails ? http.Response('down', 503) : ok('a'),
        'b.test': () => ok('b'),
        'c.test': () => ok('c'),
      }, calls),
    );
    expect(await pool.jsonRpc('x'), 'b');
    calls.clear();
    aFails = false;
    // a.test is cooling down, so b.test answers without trying a.test.
    expect(await pool.jsonRpc('x'), 'b');
    expect(calls, ['b.test']);
    expect(pool.active.host, 'b.test');
  });

  test('does not switch on errors that are the request\'s fault', () async {
    final calls = <String>[];
    final pool = RpcPool(
      urls: urls,
      client: fake({'a.test': () => rpcError(3, 'execution reverted'), 'b.test': () => ok('b')}, calls),
    );
    await expectLater(pool.jsonRpc('eth_call'), throwsA(isA<RpcException>().having((e) => e.code, 'code', 3)));
    expect(calls, ['a.test']);
    expect(pool.endpoints[0].cooldownUntil, isNull);
  });

  test('switches on JSON-RPC rate-limit errors', () async {
    final calls = <String>[];
    final pool = RpcPool(
      urls: urls,
      client: fake({'a.test': () => rpcError(-32005, 'limit exceeded'), 'b.test': () => ok('b')}, calls),
    );
    expect(await pool.jsonRpc('eth_getLogs'), 'b');
    expect(calls, ['a.test', 'b.test']);
  });

  test('throws the last error when every endpoint fails', () async {
    final pool = RpcPool(
      urls: urls,
      client: fake({for (final u in urls) Uri.parse(u).host: () => http.Response('down', 502)}, []),
    );
    await expectLater(pool.jsonRpc('x'), throwsA(isA<RpcException>()));
    expect(pool.endpoints.every((e) => e.cooldownUntil != null), isTrue);
  });
}
