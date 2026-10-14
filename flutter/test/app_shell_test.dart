import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_counter/main.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/app_state.dart';
import 'package:flutter_counter/src/state/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Answers the EVM reads the Read screen makes, with one counter change and
/// 1 ETH on every account.
/// Anything else gets a JSON-RPC error.
final fakeChain = MockClient((request) async {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  String word(int value) => value.toRadixString(16).padLeft(64, '0');
  final Object? result = switch (body['method']) {
    'eth_call' => '0x${word(3)}',
    'eth_getBalance' => '0xde0b6b3a7640000',
    'eth_blockNumber' => '0x${(11851094 + 100).toRadixString(16)}',
    'eth_getLogs' => [
      {
        'topics': ['0x00', '0x${'0' * 24}fffaa29e82d5455985a908235536d2cd01acce47'],
        'data': '0x${word(1)}${word(2)}${word(0)}',
        'transactionHash': '0xabc',
        'blockNumber': '0xb4d5a0',
      },
    ],
    'eth_getBlockByNumber' => {
      'timestamp': '0x${(DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120).toRadixString(16)}',
    },
    _ => null,
  };
  return http.Response(
    jsonEncode(
      result == null
          ? {
              'jsonrpc': '2.0',
              'id': 1,
              'error': {'code': -32601, 'message': 'not mocked'},
            }
          : {'jsonrpc': '2.0', 'id': 1, 'result': result},
    ),
    200,
  );
});

void main() {
  testWidgets('shows the four screens, reads the counter and switches networks', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(services: ChainServices(client: fakeChain));
    await tester.pumpWidget(FlutterCounterApp(state: state));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Flutter Counter'), findsOneWidget);
    expect(find.text('The counter on Sepolia'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // The one CounterChanged log, decoded: 1 -> 2 by the dev wallet.
    expect(find.textContaining('incremented'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('2 · '), findsOneWidget);

    await tester.tap(find.text('Sign in').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1. Be the wallet'), findsOneWidget);

    await tester.tap(find.text('Write').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Change your counter'), findsOneWidget);
    expect(find.text('A wallet signs every change'), findsOneWidget);

    await tester.tap(find.byKey(const Key('network-chip')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('Solana Devnet'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Solana Devnet'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.network, Networks.solanaDevnet);
    expect(
      find.descendant(of: find.byKey(const Key('network-chip')), matching: find.text('Solana Devnet')),
      findsOneWidget,
    );
  });
}
