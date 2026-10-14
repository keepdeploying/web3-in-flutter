import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/screen_layout.dart';
import '../ui/widgets/whats_happening.dart';

/// Changes your counter on the selected network: increment, decrement or
/// reset. Each one is a transaction your signer pays a small fee for.
///
/// For now (milestone M4) the buttons only play a pretend transaction so the
/// progress steps and layout can be reviewed. M8 sends real transactions.
class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, required this.onSetUpWallet});

  final VoidCallback onSetUpWallet;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  int value = 4;
  List<HappeningStep> steps = const [];
  bool busy = false;

  Future<void> pretend(String action, int Function(int) change) async {
    final network = AppScope.of(context).network;
    setState(() {
      busy = true;
      steps = [
        HappeningStep(title: 'Build the $action call', status: StepStatus.active),
        const HappeningStep(title: 'Waiting for your wallet...'),
        const HappeningStep(title: 'Sending...'),
        const HappeningStep(title: 'Confirming...'),
      ];
    });
    for (var i = 0; i < steps.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      setState(() {
        steps = [
          for (final (j, s) in steps.indexed)
            j < i + 1
                ? s.copyWith(status: StepStatus.done)
                : j == i + 1
                ? s.copyWith(status: StepStatus.active)
                : s,
        ];
      });
    }
    setState(() {
      value = change(value);
      busy = false;
      steps = [
        ...steps.take(steps.length - 1),
        steps.last.copyWith(
          status: StepStatus.done,
          detail: 'Placeholder transaction. The real one links to the ${network.name} explorer.',
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final network = AppScope.of(context).network;
    final theme = Theme.of(context);
    final accent = accentOf(network);

    return ScreenLayout(
      title: 'Change your counter',
      subtitle: 'Each change is a transaction your wallet signs and pays a small fee for.',
      aside: WhatsHappeningCard(steps: steps),
      children: [
        const DemoBanner(),
        GlassCard(
          accent: accent,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Your counter on ${network.name}', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                // Scales down instead of overflowing when the number gets long.
                child: FittedBox(
                  key: ValueKey(value),
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value',
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                      // Digits of equal width, so the number doesn't jiggle as it changes.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => pretend('increment', (v) => v + 1),
                    icon: PhosphorIcon(PhosphorIconsRegular.plus, size: 18),
                    label: const Text('Increment'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => pretend('decrement', (v) => v - 1),
                    icon: PhosphorIcon(PhosphorIconsRegular.minus, size: 18),
                    label: const Text('Decrement'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => pretend('reset', (_) => 0),
                    icon: PhosphorIcon(PhosphorIconsRegular.arrowCounterClockwise, size: 18),
                    label: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: widget.onSetUpWallet, child: const Text('No wallet yet? Set one up')),
            ],
          ),
        ),
      ],
    );
  }
}
