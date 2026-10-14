import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../backend/backend.dart';
import '../chains/networks.dart';
import '../wallet/wallet_signer.dart';
import 'connection_controller.dart';
import 'services.dart';
import 'session_controller.dart';
import 'wallet_controller.dart';

export '../backend/backend.dart' show SignInLevel;
export 'connection_controller.dart';
export 'session_controller.dart';
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

/// Labels for the sign-in levels, which the server package defines.
extension SignInLevelText on SignInLevel {
  String get label => 'Level ${index + 1}';

  String get description => switch (this) {
    SignInLevel.fixed => 'A fixed message. A copied signature works forever.',
    SignInLevel.nonce => 'A one-time nonce from the server. Stops replays, not phishing.',
    SignInLevel.standard => 'A full sign-in message: domain, chain, nonce and expiry. Stops replays and phishing.',
  };
}

/// App-wide settings and selections, shared through [AppScope].
///
/// It's a plain [ChangeNotifier]: widgets that read it rebuild when it calls
/// [notifyListeners]. No state-management package needed.
class AppState extends ChangeNotifier {
  AppState({
    ChainServices? services,
    WalletController? wallet,
    ConnectionController? connections,
    LocalBackend? localBackend,
    this.httpClient,
  }) : services = services ?? ChainServices(),
       wallet = wallet ?? WalletController(),
       connections = connections ?? ConnectionController(),
       localBackend = localBackend ?? LocalBackend() {
    // Widgets that watch the app state also rebuild when the wallets or the
    // session change.
    this.wallet.addListener(notifyListeners);
    this.connections.addListener(notifyListeners);
    session.addListener(notifyListeners);
    // The session belongs to the signer that signed in. When the signer
    // goes away (a locked wallet, a disconnected one), sign out.
    void checkSigner() {
      final signedIn = session.signer;
      if (signedIn != null && signerFor(signedIn.family) != signedIn) session.signOut();
    }

    this.wallet.addListener(checkSigner);
    this.connections.addListener(checkSigner);
  }

  /// The RPC pools and counter readers for every network.
  final ChainServices services;

  /// The in-app wallet.
  final WalletController wallet;

  /// Wallets installed on this device, and accounts connected from them.
  final ConnectionController connections;

  /// Who signs for [family]: a connected installed wallet if there is one,
  /// otherwise the in-app wallet while it is unlocked.
  WalletSigner? signerFor(ChainFamily family) => connections.signerFor(family) ?? wallet.signerFor(family);

  /// Who signs on the selected network.
  WalletSigner? get signer => signerFor(network.family);

  /// Who is signed in to the backend, and the last sign-in attempt.
  final session = SessionController();

  /// The backend that runs inside the app. Kept for the app's lifetime, so
  /// its nonces and sessions survive switching screens.
  final LocalBackend localBackend;

  /// For tests: the HTTP client the HTTP backend uses.
  final http.Client? httpClient;
  HttpBackend? _httpBackend;

  /// The backend that checks sign-ins, as chosen in Settings.
  Backend get backend => _backendMode == BackendMode.local
      ? localBackend
      : _httpBackend ??= HttpBackend(Uri.parse(_serverUrl), client: httpClient);

  Network _network = Networks.sepolia;
  ThemeMode _themeMode = ThemeMode.system;
  BackendMode _backendMode = BackendMode.local;
  SignInLevel _signInLevel = SignInLevel.standard;
  String _serverUrl = 'http://localhost:8080';

  Network get network => _network;
  ThemeMode get themeMode => _themeMode;
  BackendMode get backendMode => _backendMode;
  SignInLevel get signInLevel => _signInLevel;
  String get serverUrl => _serverUrl;

  set network(Network value) => _update(() => _network = value);
  set themeMode(ThemeMode value) => _update(() => _themeMode = value);
  set backendMode(BackendMode value) => _update(() {
    _backendMode = value;
    // A session token only means something to the backend that issued it.
    session.signOut();
  });
  set signInLevel(SignInLevel value) => _update(() => _signInLevel = value);
  set serverUrl(String value) => _update(() {
    _serverUrl = value;
    _httpBackend = null;
    session.signOut();
  });

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
