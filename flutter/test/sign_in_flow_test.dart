import 'package:flutter/material.dart';
import 'package:flutter_counter/main.dart';
import 'package:flutter_counter/src/backend/backend.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/app_state.dart';
import 'package:flutter_counter/src/state/services.dart';
import 'package:flutter_counter/src/wallet/vault.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' show CounterServer;
import 'package:flutter_test/flutter_test.dart';

import 'wallet_flow_test.dart' show devPhrase, fakeChain;

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = text.endsWith('...') ? find.textContaining(text.substring(0, text.length - 3)) : find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder.last), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder.last);
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('signs in, replays at levels 3 and 1, and saves a description', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState(
      services: ChainServices(client: fakeChain),
      wallet: WalletController(vault: MemoryVault()),
      // Offline: the dev wallet is a plain account, so no chain lookups.
      localBackend: LocalBackend(server: CounterServer()),
    );
    await state.wallet.start();
    await state.wallet.save(devPhrase, const VaultOptions());
    await tester.pumpWidget(FlutterCounterApp(state: state));
    await tester.pump(const Duration(milliseconds: 500));
    await tapText(tester, 'Sign in');

    // Level 3 is the default.
    expect(find.textContaining('wants you to sign in with your Ethereum account'), findsWidgets);
    await tapText(tester, 'Sign in as ...');
    expect(state.session.signedIn, isTrue);
    expect(find.textContaining('Signed in as 0xfFFA...ce47 at level 3'), findsOneWidget);
    expect(find.text('Domain: passed'), findsOneWidget);

    await tapText(tester, 'Replay old signature');
    expect(find.textContaining('Level 3 replay: Refused: That nonce was already used'), findsOneWidget);
    expect(find.text('Nonce: failed'), findsOneWidget);

    // Level 1: the replay works, which is the problem.
    await tapText(tester, 'Level 1');
    await tapText(tester, 'Sign in again');
    await tapText(tester, 'Replay old signature');
    expect(find.textContaining('Level 1 replay: Accepted'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'gm from the widget test');
    await tapText(tester, 'Save');
    expect(find.text('gm from the widget test'), findsOneWidget);

    await tapText(tester, 'Sign out');
    expect(state.session.signedIn, isFalse);
    expect(find.text('Sign in to write yours'), findsOneWidget);

    // Another EVM network keeps the session; another chain family ends it.
    await tapText(tester, 'Sign in as ...');
    state.network = Networks.baseSepolia;
    await tester.pumpAndSettle();
    expect(state.session.signedIn, isTrue);
    state.network = Networks.solanaDevnet;
    await tester.pumpAndSettle();
    expect(state.session.signedIn, isFalse);
    state.network = Networks.sepolia;
    await tester.pumpAndSettle();

    // Locking the wallet ends the session too.
    await tapText(tester, 'Sign in as ...');
    await state.wallet.lock();
    await tester.pumpAndSettle();
    expect(state.session.signedIn, isFalse);
  });
}
