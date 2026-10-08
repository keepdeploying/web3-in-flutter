import 'package:flutter/material.dart';

import 'src/screens/home_shell.dart';
import 'src/state/app_state.dart';
import 'src/ui/theme.dart';

/// Flutter Counter: one app that reads, authenticates and writes on EVM,
/// Solana, Sui, Cosmos and NEAR testnets.
///
/// Every chain has the same simple counter contract. The app reads it,
/// connects a wallet in one of three ways, signs in to a backend with a
/// signed message, and changes the counter with transactions. A "What's
/// happening" card on every screen explains each step.
void main() {
  runApp(FlutterCounterApp(state: AppState()));
}

class FlutterCounterApp extends StatelessWidget {
  const FlutterCounterApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: 'Flutter Counter',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: state.themeMode,
          home: const HomeShell(),
        ),
      ),
    );
  }
}
