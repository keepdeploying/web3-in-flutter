/// Colors, shapes and text styles for Flutter Counter.
///
/// The look is "glass": translucent cards over a soft, colorful background.
/// The background takes its colors from the selected network, so switching
/// from Base to Solana visibly changes the mood of the app.
library;

import 'package:flutter/material.dart';

import '../chains/networks.dart';

/// The app's base color, used when building the light and dark color schemes.
const Color seedColor = Color(0xFF5B5BD6);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  // Bars and the rail draw their own glass (see GlassBar), so they stay clear.
  const clear = Colors.transparent;
  return base.copyWith(
    scaffoldBackgroundColor: clear,
    // Pads small controls (chips, checkboxes, icon buttons) to a 48 px touch
    // target, also on desktop, where Flutter would shrink them.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(backgroundColor: clear, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: clear,
      surfaceTintColor: clear,
      elevation: 0,
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStateProperty.fromMap({
        WidgetState.selected: IconThemeData(color: scheme.onPrimaryContainer),
        WidgetState.any: IconThemeData(color: scheme.onSurfaceVariant),
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: clear,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      selectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 44))),
  );
}

/// The network's brand color.
Color accentOf(Network network) => Color(network.accent);

/// A monospace style for addresses, hashes and amounts.
TextStyle monoStyle(BuildContext context, {double? size, FontWeight? weight}) {
  return TextStyle(
    fontFamily: 'RobotoMono',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    fontSize: size,
    fontWeight: weight,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

/// Shortens `0x1234567890abcdef` to `0x1234...cdef` for display.
String shortAddress(String value, {int head = 6, int tail = 4}) {
  if (value.length <= head + tail + 3) return value;
  return '${value.substring(0, head)}...${value.substring(value.length - tail)}';
}

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String timeAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
