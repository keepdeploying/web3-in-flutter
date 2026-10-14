import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../chains/networks.dart';
import '../ui/widgets/whats_happening.dart';
import '../wallet/in_app_signer.dart';
import '../wallet/wallet_signer.dart';

/// What happened when an old signature was sent again.
class ReplayOutcome {
  const ReplayOutcome({required this.level, required this.result});

  final SignInLevel level;
  final SignInResult result;

  bool get accepted => result.ok;

  /// The lesson of the replay demo, in one sentence.
  String get explanation => accepted
      ? 'Accepted. At level 1 the message never changes, so anyone who ever saw this signature can sign in as you.'
      : 'Refused: ${result.failure?.detail}';
}

/// Signs in to the backend with a wallet, keeps the session, and replays
/// the last signature for the demo.
class SessionController extends ChangeNotifier {
  String? _token;
  Session? _session;
  bool _busy = false;
  Challenge? _lastChallenge;
  SignedMessage? _lastSigned;
  WalletSigner? _signer;
  SignInLevel? _lastLevel;
  String? _lastChainId;
  ReplayOutcome? _replay;
  List<Description> _descriptions = const [];

  String? get token => _token;
  Session? get session => _session;
  bool get busy => _busy;
  bool get signedIn => _session != null;

  /// Who signed in, or signed the last attempt.
  WalletSigner? get signer => _signer;

  /// The message the backend asked for last, to show in the preview.
  Challenge? get lastChallenge => _lastChallenge;
  bool get canReplay => _lastSigned != null;
  ReplayOutcome? get replay => _replay;
  List<Description> get descriptions => _descriptions;

  /// The whole flow, returned as steps for the "What's happening" card:
  /// ask for a challenge, sign it with [signer], send it, read the checks.
  Future<List<HappeningStep>> signIn({
    required Backend backend,
    required WalletSigner signer,
    required Network network,
    required SignInLevel level,
  }) => _run(() async {
    final steps = <HappeningStep>[];

    final challenge = await backend.challenge(
      ChallengeRequest(level: level, family: network.family, address: signer.address, chainId: network.chainId),
    );
    _lastChallenge = challenge;
    steps.add(
      HappeningStep(
        title: 'Got a challenge from the backend',
        detail: switch (level) {
          SignInLevel.fixed => 'Level 1: the same text for everyone, every time.',
          SignInLevel.nonce => 'Level 2: the text plus a one-time nonce, valid for 5 minutes.',
          SignInLevel.standard =>
            'Level 3: domain, your address, the chain, a one-time nonce and an expiry, all in the text.',
        },
        code: challenge.message,
        status: StepStatus.done,
      ),
    );

    final signed = await signer.signMessage(
      challenge.message,
      nearNonce: challenge.nearNonce == null ? null : base64Decode(challenge.nearNonce!),
    );
    _lastSigned = signed;
    _signer = signer;
    _lastLevel = level;
    _lastChainId = network.chainId;
    _replay = null;
    steps.add(
      HappeningStep(
        title: 'Signed it with ${signer is InAppSigner ? 'the in-app wallet' : signer.name}',
        detail: 'Only the signature goes to the backend. The private key never leaves the wallet.',
        code: signed.signature,
        status: StepStatus.done,
      ),
    );

    final result = await backend.signIn(signed, level: level, chainId: network.chainId);
    steps.addAll(_checkSteps(result, backend));
    if (result.ok) {
      _token = result.token;
      _session = result.session;
      await _loadDescriptions(backend);
    }
    return steps;
  });

  /// Sends the last signature again, as an attacker who copied it would.
  Future<List<HappeningStep>> replayLast(Backend backend) => _run(() async {
    final signed = _lastSigned;
    if (signed == null) return const <HappeningStep>[];
    final result = await backend.signIn(signed, level: _lastLevel!, chainId: _lastChainId!);
    _replay = ReplayOutcome(level: _lastLevel!, result: result);
    return [
      HappeningStep(
        title: 'Sent the same signature again',
        detail: 'As someone who copied it from a log or a request would. Nothing was signed this time.',
        code: signed.signature,
        status: StepStatus.done,
      ),
      ..._checkSteps(result, backend),
    ];
  });

  Future<void> loadDescriptions(Backend backend) => _run(() => _loadDescriptions(backend));

  Future<void> saveDescription(Backend backend, String text) => _run(() async {
    await backend.setDescription(_token ?? '', text);
    await _loadDescriptions(backend);
  });

  void signOut() {
    if (_session == null && _lastSigned == null) return;
    _token = null;
    _session = null;
    _lastSigned = null;
    _signer = null;
    _lastChallenge = null;
    _replay = null;
    notifyListeners();
  }

  Future<void> _loadDescriptions(Backend backend) async => _descriptions = await backend.descriptions();

  List<HappeningStep> _checkSteps(SignInResult result, Backend backend) => [
    for (final check in result.checks)
      HappeningStep(
        title: '${check.label}: ${check.passed ? 'passed' : 'failed'}',
        detail: check.detail,
        status: check.passed ? StepStatus.done : StepStatus.failed,
      ),
    if (!result.ok)
      HappeningStep(
        title: 'Not signed in',
        detail: 'The backend ${backend.description} stopped at the first failed check.',
        status: StepStatus.failed,
      ),
  ];

  Future<T> _run<T>(Future<T> Function() work) async {
    _busy = true;
    notifyListeners();
    try {
      return await work();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
