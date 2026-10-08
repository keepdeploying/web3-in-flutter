import 'package:flutter/material.dart';

import '../chains/networks.dart';

/// Where the app sends signed messages for verification.
enum BackendMode {
  /// Runs the server's Dart code inside the app. Handy for demos and the web,
  /// but a real app must verify signatures on a server it controls.
  local('In the app (simulated)'),

  /// Calls the shelf server in `server/` over HTTP.
  http('HTTP server');

  const BackendMode(this.label);
  final String label;
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
