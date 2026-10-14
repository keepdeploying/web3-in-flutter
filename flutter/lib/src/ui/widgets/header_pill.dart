import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// The glass pill the header's buttons share: an icon, a label when there
/// is room for it, and a caret. It looks 36 px tall; the tap area is 44.
class HeaderPill extends StatelessWidget {
  const HeaderPill({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.label,
    this.maxWidth = 260,
  });

  /// What screen readers announce, label shown or not.
  final String semanticLabel;
  final Widget icon;

  /// Left out on narrow windows, where the pill shows only its icon.
  final String? label;
  final VoidCallback onTap;
  final double maxWidth;

  /// Whether the window is wide enough for header labels. Phones get icons.
  static bool showLabels(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pill = Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 44, minWidth: 44, maxWidth: maxWidth),
          // widthFactor: shrink to the pill, instead of centering it in the full width.
          child: Center(
            widthFactor: 1,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(dimension: 20, child: Center(child: icon)),
                      if (label case final text?) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Without a label, a tooltip says what the icon is.
    return label == null ? Tooltip(message: semanticLabel, child: pill) : pill;
  }
}
