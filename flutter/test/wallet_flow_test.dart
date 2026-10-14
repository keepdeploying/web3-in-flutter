import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_counter/main.dart';
import 'package:flutter_counter/src/state/app_state.dart';
import 'package:flutter_counter/src/state/services.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

/// Every EVM read answers 0x0, with 1 ETH as the balance.
final fakeChain = MockClient((request) async {
  final method = (jsonDecode(request.body) as Map)['method'];
  final result = switch (method) {
    'eth_getBalance' => '0xde0b6b3a7640000',
    'eth_getLogs' => <Object>[],
    _ => '0x0',
  };
  return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': result}), 200);
});

Future<AppState> openSignIn(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(
    services: ChainServices(client: fakeChain),
    wallet: WalletController(vault: MemoryVault()),
  );
  await state.wallet.start();
  await tester.pumpWidget(FlutterCounterApp(state: state));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('Sign in').first);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  return state;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(find.text(text).last), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('creates a wallet, passes the backup quiz and signs a message', (tester) async {
    final state = await openSignIn(tester);
    expect(state.wallet.status, WalletStatus.none);

    await tapText(tester, 'Create a wallet');
    // Read the 12 words the screen shows.
    final words = [for (var i = 0; i < 12; i++) tester.widget<Text>(find.byKey(Key('phrase-word-$i'))).data!];
    expect(HdKeys.isValidMnemonic(words.join(' ')), isTrue);

    await tapText(tester, 'I wrote these words down');
    await tapText(tester, 'Next');

    // Answer the quiz: three "Word #N" questions, each with the right word as a chip.
    var answered = 0;
    for (var i = 0; i < 12; i++) {
      final chip = find.byKey(Key('quiz-$i-${words[i]}'));
      if (chip.evaluate().isEmpty) continue;
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      answered++;
    }
    expect(answered, 3);
    await tapText(tester, 'Next');

    expect(find.text('Protect it on this device'), findsOneWidget);
    await tapText(tester, 'Save the wallet');

    expect(state.wallet.status, WalletStatus.unlocked);
    expect(find.text('Your EVM account'), findsOneWidget);
    expect(find.text('1 ETH'), findsOneWidget);

    await tapText(tester, 'Sign a test message');
    expect(find.text('Wrap it (EIP-191)'), findsOneWidget);
    expect(find.text('Sign with secp256k1'), findsOneWidget);
  });

  testWidgets('imports a phrase and shows the same addresses as other wallets', (tester) async {
    final state = await openSignIn(tester);
    await tapText(tester, 'Import a phrase');

    await tester.enterText(find.byType(TextField), 'not a real phrase');
    await tester.pump();
    expect(find.textContaining('Not valid yet'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  ${devPhrase.toUpperCase()}  ');
    await tester.pump();
    expect(find.text('12 words, checksum OK.'), findsOneWidget);
    await tapText(tester, 'Next');
    await tapText(tester, 'Save the wallet');

    expect(find.text('0xfFFAa29e82d5455985a908235536d2cD01aCce47'), findsOneWidget);
    expect(
      state.wallet.keyFor(ChainFamily.near)!.address,
      '92b28ade98c901eaeb5cd6de863d7b5e9684ca2718c7efd556af051cc4ac5670',
    );

    // Lock, then unlock again.
    await state.wallet.lock();
    await tester.pumpAndSettle();
    expect(find.text('Unlock'), findsOneWidget);
    await tapText(tester, 'Unlock');
    expect(state.wallet.status, WalletStatus.unlocked);
  });
}
