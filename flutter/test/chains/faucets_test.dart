import 'dart:convert';

import 'package:flutter_counter/src/chains/faucets.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Solana passes on the airdrop limit message', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'error': {'code': 429, 'message': "You've either reached your airdrop limit today"},
        }),
        429,
      ),
    );
    await expectLater(
      Faucets.fund(Networks.solanaDevnet, 'DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX', client: client),
      throwsA(predicate((e) => '$e'.contains('airdrop limit'))),
    );
  });

  test('Solana returns the airdrop signature', () async {
    final client = MockClient((request) async {
      expect(request.url, Faucets.solanaAirdrop);
      expect((jsonDecode(request.body) as Map)['method'], 'requestAirdrop');
      return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': '5sig'}), 200);
    });
    final result = await Faucets.fund(
      Networks.solanaDevnet,
      'DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX',
      client: client,
    );
    expect(result.txId, '5sig');
  });

  test('NEAR posts the account ID and returns the faucet message', () async {
    final client = MockClient((request) async {
      expect(request.url, Faucets.nearFaucet);
      expect(jsonDecode(request.body), {'accountId': 'abc.testnet'});
      return http.Response(jsonEncode({'success': true, 'message': 'Funded abc.testnet with 5 NEAR'}), 200);
    });
    final result = await Faucets.fund(Networks.nearTestnet, 'abc.testnet', client: client);
    expect(result.message, contains('5 NEAR'));
  });
}
