import 'package:flutter/material.dart';
import 'package:flutter_counter/main.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the four screens and switches networks', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await tester.pumpWidget(FlutterCounterApp(state: state));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('Flutter Counter'), findsOneWidget);
    expect(find.text('The counter on Sepolia'), findsOneWidget);

    await tester.tap(find.text('Sign in').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1. Be the wallet'), findsOneWidget);

    await tester.tap(find.text('Write').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your counter on Sepolia'), findsOneWidget);

    await tester.tap(find.byType(ActionChip));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('Solana Devnet'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Solana Devnet'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.network, Networks.solanaDevnet);
    expect(find.text('Your counter on Solana Devnet'), findsOneWidget);
  });
}
