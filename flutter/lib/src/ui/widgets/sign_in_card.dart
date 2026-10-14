import 'package:flutter/material.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' show SignInMessages, StandardMessage, AppIdentity;
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../state/app_state.dart';
import '../theme.dart';
import 'glass.dart';
import 'whats_happening.dart';

/// Signs in to the backend with the connected wallet, at the chosen level,
/// and replays the last signature to show what each level protects against.
class SignInCard extends StatelessWidget {
  const SignInCard({super.key, required this.onSteps});

  /// Receives the steps of each attempt, for the "What's happening" card.
  final ValueChanged<List<HappeningStep>> onSteps;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.session;
    final theme = Theme.of(context);
    final signer = state.wallet.signerFor(state.network.family);

    Future<void> run(Future<List<HappeningStep>> Function() attempt) async {
      try {
        onSteps(await attempt());
      } catch (e) {
        onSteps([
          HappeningStep(
            title: 'Could not reach the backend',
            detail: '$e\nIs the server running? Check the backend in Settings.',
            status: StepStatus.failed,
          ),
        ]);
      }
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(title: 'Sign in to the backend', icon: PhosphorIconsDuotone.shieldCheck),
          Text(
            'Sign a message with your wallet. The backend checks the signature and gives you a session. '
            'Checks run ${state.backend.description}.',
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<SignInLevel>(
              showSelectedIcon: false,
              segments: [for (final level in SignInLevel.values) ButtonSegment(value: level, label: Text(level.label))],
              selected: {state.signInLevel},
              onSelectionChanged: session.busy ? null : (s) => state.signInLevel = s.first,
            ),
          ),
          const SizedBox(height: 8),
          Text(state.signInLevel.description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Text(
            session.lastChallenge?.level == state.signInLevel ? 'The message you signed' : 'What you will sign',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_preview(state), style: monoStyle(context, size: 12.5)),
          ),
          const SizedBox(height: 16),
          if (session.signedIn) ...[_SignedInBanner(state: state), const SizedBox(height: 12)],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: signer == null || session.busy
                    ? null
                    : () => run(
                        () => session.signIn(
                          backend: state.backend,
                          signer: signer,
                          network: state.network,
                          level: state.signInLevel,
                        ),
                      ),
                icon: session.busy
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(PhosphorIconsRegular.signIn, size: 18),
                label: Text(
                  signer == null
                      ? 'Sign in (unlock a wallet first)'
                      : session.signedIn
                      ? 'Sign in again'
                      : 'Sign in as ${shortAddress(signer.address)}',
                ),
              ),
              if (session.canReplay)
                OutlinedButton.icon(
                  onPressed: session.busy ? null : () => run(() => session.replayLast(state.backend)),
                  icon: const Icon(PhosphorIconsRegular.repeat, size: 18),
                  label: const Text('Replay old signature'),
                ),
              if (session.signedIn)
                TextButton.icon(
                  onPressed: session.busy ? null : session.signOut,
                  icon: const Icon(PhosphorIconsRegular.signOut, size: 18),
                  label: const Text('Sign out'),
                ),
            ],
          ),
          if (session.replay case final replay?) ...[const SizedBox(height: 12), _ReplayBanner(replay: replay)],
        ],
      ),
    );
  }

  /// The last real challenge for this level, or what one will look like.
  static String _preview(AppState state) {
    final last = state.session.lastChallenge;
    if (last != null && last.level == state.signInLevel) return last.message;
    const nonce = 'chosen-by-the-server';
    final address = state.wallet.keyFor(state.network.family)?.address ?? 'your address';
    final now = DateTime.now().toUtc();
    return switch (state.signInLevel) {
      SignInLevel.fixed => SignInMessages.fixed(),
      SignInLevel.nonce => SignInMessages.withNonce(nonce),
      SignInLevel.standard => SignInMessages.standard(
        StandardMessage(
          domain: const AppIdentity().domain,
          family: state.network.family,
          address: address,
          statement: const AppIdentity().statement,
          uri: const AppIdentity().uri,
          chainId: state.network.chainId,
          nonce: nonce,
          issuedAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
      ),
    };
  }
}

class _SignedInBanner extends StatelessWidget {
  const _SignedInBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session.session!;
    final theme = Theme.of(context);
    final minutes = session.expiresAt.difference(DateTime.now().toUtc()).inMinutes;
    return _Banner(
      icon: PhosphorIconsFill.checkCircle,
      color: Colors.green.shade600,
      text:
          'Signed in as ${shortAddress(session.address)} at ${session.level.label.toLowerCase()}. '
          'The session token is valid for $minutes more minutes.',
      style: theme.textTheme.bodyMedium,
    );
  }
}

class _ReplayBanner extends StatelessWidget {
  const _ReplayBanner({required this.replay});

  final ReplayOutcome replay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Banner(
      // At level 1 the replay "works", and that is the bad news.
      icon: replay.accepted ? PhosphorIconsFill.warning : PhosphorIconsFill.shieldCheck,
      color: replay.accepted ? scheme.error : Colors.green.shade600,
      text: '${replay.level.label} replay: ${replay.explanation}',
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text, this.style});

  final IconData icon;
  final Color color;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
