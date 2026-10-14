/// The "glass" building blocks: a colorful background and translucent cards
/// that blur whatever is behind them.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// A soft gradient with three large, blurred color blobs.
///
/// [accent] is the selected network's color. When it changes, the blobs
/// slide to the new color, so the whole app takes on the network's mood.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF0B0B14) : const Color(0xFFF4F4FB);
    // Two companion colors, rotated around the color wheel from the accent.
    final hsl = HSLColor.fromColor(accent);
    final second = hsl.withHue((hsl.hue + 40) % 360).toColor();
    final third = hsl.withHue((hsl.hue + 300) % 360).toColor();
    final strength = dark ? 0.45 : 0.30;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: accent),
      duration: const Duration(milliseconds: 600),
      builder: (context, color, _) {
        final c = color ?? accent;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: base),
            _Blob(
              alignment: const Alignment(-1.1, -1.0),
              color: c.withValues(alpha: strength),
              size: 520,
            ),
            _Blob(
              alignment: const Alignment(1.2, -0.2),
              color: second.withValues(alpha: strength * 0.8),
              size: 460,
            ),
            _Blob(
              alignment: const Alignment(-0.4, 1.3),
              color: third.withValues(alpha: strength * 0.7),
              size: 500,
            ),
            // One blur over all the blobs turns them into a smooth wash.
            BackdropFilter(filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90), child: const SizedBox.expand()),
            child,
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.alignment, required this.color, required this.size});

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// A translucent, blurred, rounded card. Every section of the app sits in one.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.accent});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// An optional color for a thin top edge, to tie the card to a network.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // Blurs what is behind the card, not the card's own content.
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // A touch more white in dark mode, so cards stand out from the
            // dark background and their text keeps its contrast.
            color: Colors.white.withValues(alpha: dark ? 0.08 : 0.55),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.14 : 0.7)),
            gradient: accent == null
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [
                      accent!.withValues(alpha: dark ? 0.18 : 0.14),
                      Colors.transparent,
                    ],
                  ),
          ),
          // A transparent Material, so list tiles, chips and buttons inside the
          // card draw their ink splashes on the card instead of under it.
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A frosted strip for the navigation bar and the navigation rail: the same
/// blur as [GlassCard], over the colorful background.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child, this.vertical = false, this.bothSides = false});

  final Widget child;

  /// Whether this is a side rail (a divider on its right) instead of a bottom
  /// bar (a divider on top).
  final bool vertical;

  /// For a rail away from the window's edge: a divider on its left too.
  final bool bothSides;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6));
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.7),
            border: vertical
                ? Border(right: divider, left: bothSides ? divider : BorderSide.none)
                : Border(top: divider),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Which color family an [IconTile] draws from.
enum IconTone { primary, tertiary, neutral }

/// An icon on a tinted tile, the one look for every "icon in a box" in the app.
///
/// The tile is solid enough to read on a light glass card, and in dark mode it
/// switches to a dim tile with a bright icon, since a pale tile would glare.
/// Duotone icons get a faint second layer so they keep their depth.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.size = 32,
    this.iconSize = 18,
    this.circle = false,
    this.tone = IconTone.primary,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final bool circle;
  final IconTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final (container, onContainer, accent) = switch (tone) {
      IconTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer, scheme.primary),
      IconTone.tertiary => (scheme.tertiaryContainer, scheme.onTertiaryContainer, scheme.tertiary),
      IconTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurface, scheme.onSurface),
    };
    final color = dark ? accent : onContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
        color: container.withValues(alpha: dark ? 0.45 : 0.9),
      ),
      child: PhosphorIcon(
        icon,
        size: iconSize,
        color: color,
        duotoneSecondaryOpacity: 0.35,
        duotoneSecondaryColor: color,
      ),
    );
  }
}

/// A small title above a card's content, with an optional trailing widget.
///
/// The [icon] (a duotone one, like `PhosphorIconsDuotone.wallet`) sits in a
/// soft rounded tile, the same on every card. A [leading] widget, like a
/// network logo, takes the tile's place.
class CardHeader extends StatelessWidget {
  const CardHeader({super.key, required this.title, this.icon, this.leading, this.trailing});

  final String title;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lead = leading ?? (icon == null ? null : IconTile(icon: icon!));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 10)],
          Expanded(
            child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
