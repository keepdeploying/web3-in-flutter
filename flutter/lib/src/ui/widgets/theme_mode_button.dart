import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../state/app_state.dart';
import 'header_pill.dart';

/// Light, dark, or whatever the system uses.
extension ThemeModeText on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  IconData get icon => switch (this) {
    ThemeMode.system => PhosphorIconsRegular.circleHalf,
    ThemeMode.light => PhosphorIconsRegular.sun,
    ThemeMode.dark => PhosphorIconsRegular.moon,
  };
}

/// The header button that picks the theme, from a small menu.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final mode = state.themeMode;
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      menuChildren: [
        for (final option in ThemeMode.values)
          MenuItemButton(
            key: Key('theme-${option.name}'),
            leadingIcon: PhosphorIcon(option.icon, size: 18),
            trailingIcon: option == mode
                ? PhosphorIcon(PhosphorIconsBold.check, size: 16, color: scheme.primary)
                : const SizedBox(width: 16),
            onPressed: () => state.themeMode = option,
            child: Padding(padding: const EdgeInsets.only(right: 24), child: Text(option.label)),
          ),
      ],
      builder: (context, controller, _) => HeaderPill(
        key: const Key('theme-button'),
        semanticLabel: 'Theme: ${mode.label}',
        label: HeaderPill.showLabels(context) ? mode.label : null,
        icon: PhosphorIcon(mode.icon, size: 18),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
