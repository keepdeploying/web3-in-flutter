import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'glass.dart';

/// Where a step is: not started, running, finished or failed.
enum StepStatus { pending, active, done, failed }

/// One step of an operation, as the "What's happening" card shows it.
///
/// For example: "Signed the message", "Server checked the nonce", or "Sent
/// the transaction", with the details a curious user (or a reader of the
/// article) wants to see, like the exact message or the transaction hash.
class HappeningStep {
  const HappeningStep({required this.title, this.detail, this.status = StepStatus.pending, this.link, this.code});

  final String title;
  final String? detail;
  final StepStatus status;

  /// An explorer link, opened in the browser when tapped.
  final Uri? link;

  /// Raw data to show in a monospace block: a message, a hash, a JSON body.
  final String? code;

  HappeningStep copyWith({StepStatus? status, String? detail, Uri? link, String? code}) => HappeningStep(
    title: title,
    detail: detail ?? this.detail,
    status: status ?? this.status,
    link: link ?? this.link,
    code: code ?? this.code,
  );
}

/// Explains, step by step, what the app just did on the blockchain.
///
/// Every screen has one. It turns the app into a teaching tool: you see what
/// was read, what was signed, what the backend checked and which transaction
/// was sent.
class WhatsHappeningCard extends StatelessWidget {
  const WhatsHappeningCard({super.key, required this.steps, this.title = "What's happening"});

  final String title;
  final List<HappeningStep> steps;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(title: title, icon: PhosphorIconsDuotone.lightbulb),
          if (steps.isEmpty) const _EmptyState(),
          for (final (i, step) in steps.indexed) _StepRow(step: step, isLast: i == steps.length - 1),
        ],
      ),
    );
  }
}

/// What the card shows before anything has happened.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          const SizedBox(height: 4),
          const IconTile(icon: PhosphorIconsDuotone.lightbulb, size: 72, iconSize: 40, circle: true),
          const SizedBox(height: 12),
          Text(
            'Nothing yet. Steps appear here as the app talks to the chain.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final HappeningStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (step.status) {
      StepStatus.pending => PhosphorIcon(PhosphorIconsRegular.circle, size: 20, color: scheme.outline),
      // Not an icon: the spinner shows that something is still going on.
      StepStatus.active => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
      ),
      StepStatus.done => PhosphorIcon(PhosphorIconsFill.checkCircle, size: 20, color: Colors.green),
      StepStatus.failed => PhosphorIcon(PhosphorIconsFill.xCircle, size: 20, color: scheme.error),
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              icon,
              if (!isLast) Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (step.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(step.detail!, style: theme.textTheme.bodyMedium),
                    ),
                  if (step.code != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        step.code!,
                        style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  if (step.link != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => launchUrl(step.link!),
                      icon: PhosphorIcon(PhosphorIconsRegular.arrowSquareOut, size: 16),
                      label: const Text('View on explorer'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
