import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../layout.dart';
import 'glass.dart';

/// The scrollable page every screen puts its cards in: a header, the cards,
/// and an optional [aside] that explains what is happening.
///
/// On an expanded window the [aside] gets a side panel of its own, with its
/// own scroll, so it stays in view while the main column scrolls. On smaller
/// windows it simply becomes the last card of the list.
class ScreenLayout extends StatelessWidget {
  const ScreenLayout({super.key, required this.children, this.aside, this.title, this.subtitle});

  final List<Widget> children;

  /// The "What's happening" card. Leave it out for a screen that has none, and
  /// the main column centers.
  final Widget? aside;

  final String? title;
  final String? subtitle;

  /// The widest the main column grows, so lines of text stay readable.
  static const double mainMaxWidth = 760;

  /// The width of the side panel, and the gap around it and the main column.
  static const double asideWidth = 380;
  static const double gap = 16;

  @override
  Widget build(BuildContext context) {
    final sidePanel = aside != null && WindowSize.of(context).isExpanded;
    // The glass bottom bar floats over the page (the shell extends the body
    // behind it), so the last card needs room to scroll clear of it.
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    final items = [if (title != null) _PageHeader(title: title!, subtitle: subtitle), ...children];

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in [...items, if (!sidePanel) ?aside].indexed) ...[
          if (i > 0) const SizedBox(height: gap),
          child,
        ],
      ],
    );
    if (!sidePanel) {
      return ListView(
        padding: EdgeInsets.fromLTRB(gap, 8, gap, bottom),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: mainMaxWidth),
              child: column,
            ),
          ),
        ],
      );
    }

    // The column and the panel are centered as one group, so a very wide window
    // does not leave a gap between them. Below the width where both fit, the
    // column shrinks and the panel keeps its width.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: gap),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: mainMaxWidth),
                child: ListView(
                  padding: EdgeInsets.only(top: 8, bottom: bottom),
                  children: [column],
                ),
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: asideWidth,
              child: ListView(
                padding: EdgeInsets.only(top: 8, bottom: bottom),
                children: [aside!],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// A short banner that marks data as made up, until the real reads land.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          PhosphorIcon(PhosphorIconsRegular.flask, color: scheme.tertiary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Design preview: the numbers on this screen are placeholders.')),
        ],
      ),
    );
  }
}
