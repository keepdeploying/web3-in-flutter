/// How the app adapts to the size of its window.
library;

import 'package:flutter/widgets.dart';

/// The window size classes of Material 3, chosen by the window's width.
///
/// Every screen asks for the class instead of comparing pixels itself, so
/// "what is a phone" is decided in exactly one place.
enum WindowSize {
  /// Phones: a bottom navigation bar, and one column of cards.
  compact,

  /// Small tablets and narrow desktop windows: a navigation rail on the left.
  medium,

  /// Large tablets and desktops: an extended rail, and a side panel that
  /// explains what the app is doing.
  expanded;

  /// The width where [medium] starts.
  static const double mediumFrom = 600;

  /// The width where [expanded] starts.
  static const double expandedFrom = 1200;

  /// Windows shorter than this get tighter spacing, like a phone in landscape.
  /// Only the spacing: a wide, short window still gets the rail, which uses
  /// the spare width instead of the scarce height.
  static const double shortHeight = 500;

  /// The class for a window of the given [size].
  static WindowSize forSize(Size size) {
    if (size.width < mediumFrom) return compact;
    return size.width < expandedFrom ? medium : expanded;
  }

  /// The class for the window [context] is in. Rebuilds when it is resized.
  static WindowSize of(BuildContext context) => forSize(MediaQuery.sizeOf(context));

  /// Whether [context] is in a window too short for the usual spacing, like
  /// a phone in landscape.
  static bool isShort(BuildContext context) => MediaQuery.sizeOf(context).height < shortHeight;

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}
