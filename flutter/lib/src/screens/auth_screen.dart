import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/app_state.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/installed_wallet_card.dart';
import '../ui/widgets/descriptions_card.dart';
import '../ui/widgets/screen_layout.dart';
import '../ui/widgets/sign_in_card.dart';
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
    HappeningStep(title: 'Connect a signer', detail: 'Unlock the in-app wallet, or connect one you have.'),
    HappeningStep(
      title: 'Get a challenge',
      detail: 'The backend writes the message to sign. Levels 2 and 3 add a one-time nonce.',
    ),
    HappeningStep(title: 'Sign the message', detail: 'Your wallet signs it. Only the signature leaves the wallet.'),
    HappeningStep(
      title: 'Verify',
      detail: 'The backend checks the signature and the message, then gives you a session.',
    ),
    HappeningStep(title: 'Try a replay', detail: 'Send the same signature again and see which levels refuse it.'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ScreenLayout(
      title: 'Connect and sign in',
      subtitle:
          'Each option ends in the same place: an address that can sign messages and transactions on '
          '${state.network.name}.',
      aside: WhatsHappeningCard(steps: steps ?? overview),
      children: [
        InAppWalletCard(onSteps: (value) => setState(() => steps = value)),
        InstalledWalletCard(onSteps: (value) => setState(() => steps = value)),
        const _SdkCard(
          number: 3,
          icon: PhosphorIconsRegular.puzzlePiece,
          title: 'Use an SDK',
          body:
              'Reown AppKit opens one modal with hundreds of wallets over WalletConnect, so you '
              "don't write the connection code yourself. Android and iOS.",
          action: 'Connect with Reown',
        ),
        SignInCard(onSteps: (value) => setState(() => steps = value)),
        const DescriptionsCard(),
      ],
    );
  }
}

class _SdkCard extends StatelessWidget {
  const _SdkCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;

  /// The button's label. The button stays disabled: this option isn't built.
  final String action;

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
                OutlinedButton(onPressed: null, child: Text(action)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
