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
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface.withValues(alpha: 0.6),
      indicatorColor: scheme.primaryContainer,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
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
