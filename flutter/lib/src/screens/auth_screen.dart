import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/screen_layout.dart';
import '../ui/widgets/wallet_card.dart';
import '../ui/widgets/whats_happening.dart';

/// The three ways to get a signer, then signing in to the backend.
///
/// 1. Be the wallet: the app holds the keys itself.
/// 2. Use a wallet already on the device, talking to it directly.
/// 3. Use an SDK (Reown) that does the wallet plumbing for you.
///
/// Whichever you pick, the rest of the app sees the same thing: a signer
/// that has an address and can sign messages and send counter calls.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  /// Steps from the last thing the user did, like signing a test message.
  List<HappeningStep>? steps;

  static const overview = [
    HappeningStep(title: 'Connect a signer', detail: 'Pick one of the three options above.'),
    HappeningStep(title: 'Get a challenge', detail: 'The backend gives a one-time nonce (levels 2 and 3).'),
    HappeningStep(title: 'Sign the message', detail: 'Your wallet signs it with your private key.'),
    HappeningStep(title: 'Verify', detail: 'The backend recovers or checks the signer and the message.'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return ScreenLayout(
      title: 'Connect and sign in',
      subtitle:
          'Each option ends in the same place: an address that can sign messages and transactions on '
          '${state.network.name}.',
      aside: WhatsHappeningCard(steps: steps ?? overview),
      children: [
        InAppWalletCard(onSteps: (value) => setState(() => steps = value)),
        const _BranchCard(
          number: 2,
          icon: PhosphorIconsRegular.deviceMobile,
          title: 'Use a wallet on this device',
          body:
              'Talk to wallets you already have, with no SDK: Phantom and Solflare deep links and the '
              'Mobile Wallet Adapter on phones, and browser extensions on the web.',
          milestone: 'M9',
        ),
        const _BranchCard(
          number: 3,
          icon: PhosphorIconsRegular.puzzlePiece,
          title: 'Use an SDK',
          body:
              'Reown AppKit opens one modal with hundreds of wallets over WalletConnect, so you '
              "don't write the connection code yourself. Android and iOS.",
          milestone: 'M10',
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Sign in to the backend', icon: PhosphorIconsDuotone.shieldCheck),
              const Text('After connecting, sign a message. The backend checks the signature and gives you a session.'),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<SigningLevel>(
                  showSelectedIcon: false,
                  segments: [
                    for (final level in SigningLevel.values) ButtonSegment(value: level, label: Text(level.label)),
                  ],
                  selected: {state.signingLevel},
                  onSelectionChanged: (s) => state.signingLevel = s.first,
                ),
              ),
              const SizedBox(height: 8),
              Text(state.signingLevel.description, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Text('Message preview', style: theme.textTheme.labelMedium),
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
              FilledButton(
                onPressed: null,
                child: Text(
                  state.wallet.status == WalletStatus.unlocked
                      ? 'Sign in (arrives in M7)'
                      : 'Sign in (connect a wallet first)',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _preview(AppState state) => switch (state.signingLevel) {
    SigningLevel.fixed => 'Sign in to Flutter Counter',
    SigningLevel.nonce => 'Sign in to Flutter Counter\n\nNonce: 7Hq2k9Xa...',
    SigningLevel.standard =>
      'flutter-counter.app wants you to sign in with your ${state.network.family.label} account:\n'
          '${state.wallet.keyFor(state.network.family)?.address ?? 'your address'}\n\n'
          'Sign in to Flutter Counter.\n\n'
          'URI: https://flutter-counter.app\n'
          'Version: 1\n'
          'Chain ID: ${state.network.chainId}\n'
          'Nonce: 7Hq2k9Xa...\n'
          'Issued At: 2026-10-08T12:00:00Z\n'
          'Expiration Time: 2026-10-08T12:05:00Z',
  };
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.milestone,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final String milestone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, size: 40, iconSize: 22, circle: true),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$number. $title', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(body),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: null, child: Text('Coming in $milestone')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
