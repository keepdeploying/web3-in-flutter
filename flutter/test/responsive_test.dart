import 'package:flutter/material.dart';
import 'package:flutter_counter/main.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/app_state.dart';
import 'package:flutter_counter/src/state/services.dart';
import 'package:flutter_counter/src/ui/widgets/network_picker.dart' show networkListKey;
import 'package:flutter_counter/src/wallet/vault.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_shell_test.dart' show fakeChain;

const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';
const devAddress = '0xfFFAa29e82d5455985a908235536d2cD01aCce47';

/// Window sizes from a small phone to a 4K-class desktop, as logical pixels.
const sizes = {
  '320x640 small phone': Size(320, 640),
  '390x844 phone': Size(390, 844),
  '844x390 phone in landscape': Size(844, 390),
  '820x1180 tablet': Size(820, 1180),
  '1024x768 small desktop': Size(1024, 768),
  '1440x900 desktop': Size(1440, 900),
  '2560x1440 large desktop': Size(2560, 1440),
};

/// Layout overflows are thrown as exceptions while a widget is laid out, and
/// the test framework keeps the first one. So after every step, none must be
/// waiting.
void expectNoOverflow(WidgetTester tester, String step) {
  expect(tester.takeException(), isNull, reason: 'Layout error at: $step');
}

/// Lets animations and fake network answers finish. The first pump starts the
/// animations, the second one plays them.
Future<void> settle(WidgetTester tester, [int milliseconds = 600]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: milliseconds));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<AppState> pumpApp(WidgetTester tester, Size size, double textScale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  final state = AppState(
    services: ChainServices(client: fakeChain),
    wallet: WalletController(vault: MemoryVault()),
  );
  await state.wallet.start();
  await tester.pumpWidget(FlutterCounterApp(state: state));
  await settle(tester, 1500);
  expectNoOverflow(tester, 'first frame');
  return state;
}

/// Taps a destination in the bottom bar or the rail, which show the same labels.
Future<void> goTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await settle(tester);
  expectNoOverflow(tester, label);
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // Scrolling lays out on the next frame, and a tap needs the new position.
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text).last);

void main() {
  testWidgets('a phone in landscape gets the navigation rail, not the bottom bar', (tester) async {
    await pumpApp(tester, const Size(844, 390), 1.0);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('$name, text scale $scale: every screen and the network picker fit', (tester) async {
        final state = await pumpApp(tester, size, scale);

        // Read: look up an account, so the balance and counter show too.
        await tester.enterText(find.byType(TextField), devAddress);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
        expectNoOverflow(tester, 'Read, account looked up');

        await goTo(tester, 'Sign in');
        await goTo(tester, 'Write');
        // No wallet yet: the screen explains why a wallet is needed.
        expect(find.text('A wallet signs every change'), findsOneWidget);
        expectNoOverflow(tester, 'Write, without a wallet');

        await goTo(tester, 'Settings');
        await tap(tester, find.byType(ExpansionTile).first);
        expectNoOverflow(tester, 'Settings, one network opened');

        // The picker: a sheet on phones, a dialog on bigger windows. Pick the
        // network with the longest addresses, whose reads all fail here.
        await tester.tap(find.byKey(const Key('network-chip')));
        await settle(tester);
        expectNoOverflow(tester, 'network picker');
        // Other screens also show network names, so look only inside the picker's list. On a short screen Sui Testnet
        // starts out of view.
        final list = find.byKey(networkListKey);
        final sui = find.descendant(of: list, matching: find.text('Sui Testnet'));
        await tester.scrollUntilVisible(
          sui,
          80,
          scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
        );
        await tester.pump();
        await tester.tap(sui);
        await settle(tester);
        expect(state.network, Networks.suiTestnet, reason: 'tapping the row selects the network');
        expect(list, findsNothing, reason: 'the picker closes');
        expect(find.byKey(const Key('network-chip')), findsOneWidget);
        // Phones show the network's logo only; wider windows add its name.
        expect(
          find.descendant(of: find.byKey(const Key('network-chip')), matching: find.text('Sui Testnet')),
          size.width >= 600 ? findsOneWidget : findsNothing,
        );
        expect(find.bySemanticsLabel('Network: Sui Testnet'), findsOneWidget);
        expectNoOverflow(tester, 'after picking Sui Testnet');

        await goTo(tester, 'Read');
        await goTo(tester, 'Sign in');
        await goTo(tester, 'Write');
      });
    }
  }

  // The wallet card and the setup screens, which only show with a wallet.
  for (final (name, size, scale) in [
    ('320x640 small phone', const Size(320, 640), 1.3),
    ('1440x900 desktop', const Size(1440, 900), 1.0),
  ]) {
    testWidgets('$name, text scale $scale: importing the dev phrase and the wallet card fit', (tester) async {
      final state = await pumpApp(tester, size, scale);
      await goTo(tester, 'Sign in');

      await tapText(tester, 'Import a phrase');
      expectNoOverflow(tester, 'import step');
      await tester.enterText(find.byType(TextField), devPhrase);
      await settle(tester);
      await tapText(tester, 'Next');
      expectNoOverflow(tester, 'protect step');
      await tapText(tester, 'Save the wallet');
      expect(state.wallet.status, WalletStatus.unlocked);
      expectNoOverflow(tester, 'wallet card');

      await tapText(tester, 'Your addresses on every chain');
      expectNoOverflow(tester, 'addresses on every chain');
      await tapText(tester, 'Sign a test message');
      expectNoOverflow(tester, 'signed message steps');

      // Every network has its own address format, so look at each one.
      for (final network in Networks.all) {
        state.network = network;
        await settle(tester);
        expectNoOverflow(tester, 'wallet card on ${network.name}');
      }

      // The counter card with real numbers, or a read error where the fake
      // chain doesn't answer.
      await goTo(tester, 'Write');
      for (final network in Networks.all) {
        state.network = network;
        await settle(tester);
        expect(find.text('Increment'), findsOneWidget);
        expectNoOverflow(tester, 'Write on ${network.name}');
      }

      await state.wallet.lock();
      await settle(tester);
      expectNoOverflow(tester, 'locked wallet');
    });
  }
}
