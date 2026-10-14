import 'package:flutter/material.dart';

import '../chains/networks.dart';
import 'services.dart';
import 'wallet_controller.dart';

export 'wallet_controller.dart';

/// Where the app sends signed messages for verification.
enum BackendMode {
  /// Runs the server's Dart code inside the app. Handy for demos and the web,
  /// but a real app must verify signatures on a server it controls.
  local(
    'In the app (simulated)',
    'In the app',
    "Runs the server's code inside the app, so it is simulated: fine for demos, but a real app must verify "
        'signatures on a server it controls.',
  ),

  /// Calls the shelf server in `server/` over HTTP.
  http('HTTP server', 'HTTP server', 'Sends the signed message to the shelf server in server/, like a real app does.');

  const BackendMode(this.label, this.shortLabel, this.description);

  /// The full name.
  final String label;

  /// A name short enough for a segmented button on a phone.
  final String shortLabel;

  /// One sentence about what this mode does, shown under the button.
  final String description;
}

/// How much the signed sign-in message protects against replay and phishing.
/// The app lets you switch between them to compare.
enum SigningLevel {
  fixed('Level 1', 'A fixed message. A copied signature works forever.'),
  nonce('Level 2', 'A one-time nonce from the server. Stops replays, not phishing.'),
  standard('Level 3', 'A structured message (SIWE style) with domain, nonce and expiry.');

  const SigningLevel(this.label, this.description);
  final String label;
  final String description;
}

/// App-wide settings and selections, shared through [AppScope].
///
/// It's a plain [ChangeNotifier]: widgets that read it rebuild when it calls
/// [notifyListeners]. No state-management package needed.
class AppState extends ChangeNotifier {
  AppState({ChainServices? services, WalletController? wallet})
    : services = services ?? ChainServices(),
      wallet = wallet ?? WalletController() {
    // Widgets that watch the app state also rebuild when the wallet changes.
    this.wallet.addListener(notifyListeners);
  }

  /// The RPC pools and counter readers for every network.
  final ChainServices services;

  /// The in-app wallet (branch A).
  final WalletController wallet;

  Network _network = Networks.sepolia;
  ThemeMode _themeMode = ThemeMode.system;
  BackendMode _backendMode = BackendMode.local;
  SigningLevel _signingLevel = SigningLevel.standard;
  String _serverUrl = 'http://localhost:8080';

  Network get network => _network;
  ThemeMode get themeMode => _themeMode;
  BackendMode get backendMode => _backendMode;
  SigningLevel get signingLevel => _signingLevel;
  String get serverUrl => _serverUrl;

  set network(Network value) => _update(() => _network = value);
  set themeMode(ThemeMode value) => _update(() => _themeMode = value);
  set backendMode(BackendMode value) => _update(() => _backendMode = value);
  set signingLevel(SigningLevel value) => _update(() => _signingLevel = value);
  set serverUrl(String value) => _update(() => _serverUrl = value);

  void _update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

/// Makes the [AppState] available to every widget below it.
///
/// Call `AppScope.of(context)` to read it. The calling widget rebuilds
/// whenever the state changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget.');
    return scope!.notifier!;
  }
}
