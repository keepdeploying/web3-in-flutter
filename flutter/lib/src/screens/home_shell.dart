import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../state/app_state.dart';
import '../ui/layout.dart';
import '../ui/theme.dart';
import '../ui/widgets/app_icon.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/network_picker.dart';
import 'auth_screen.dart';
import 'read_screen.dart';
import 'settings_screen.dart';
import 'write_screen.dart';

/// The app's frame: the background, the top bar with the network picker, and
/// navigation between the four screens.
///
/// The navigation follows the window size (see [WindowSize]): a glass bar at
/// the bottom on phones, a rail on the left on tablets, and an extended rail
/// with labels beside the icons on large windows.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  /// The four destinations. The icon is drawn regular, and filled when selected.
  static const destinations = <({IconData icon, IconData selected, String label})>[
    (icon: PhosphorIconsRegular.magnifyingGlass, selected: PhosphorIconsFill.magnifyingGlass, label: 'Read'),
    (icon: PhosphorIconsRegular.key, selected: PhosphorIconsFill.key, label: 'Sign in'),
    (icon: PhosphorIconsRegular.pencilLine, selected: PhosphorIconsFill.pencilLine, label: 'Write'),
    (icon: PhosphorIconsRegular.slidersHorizontal, selected: PhosphorIconsFill.slidersHorizontal, label: 'Settings'),
  ];

  void goTo(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final size = WindowSize.of(context);

    final screen = switch (index) {
      0 => ReadScreen(onSetUpWallet: () => goTo(1)),
      1 => const AuthScreen(),
      2 => WriteScreen(onSetUpWallet: () => goTo(1)),
      _ => const SettingsScreen(),
    };

    final content = Column(
      children: [
        _TopBar(size: size),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(key: ValueKey(index), child: screen),
          ),
        ),
      ],
    );

    return GlassBackground(
      accent: accentOf(state.network),
      child: Scaffold(
        // The page scrolls behind the glass bottom bar, so the bar can blur it.
        extendBody: true,
        body: size.isCompact
            ? SafeArea(bottom: false, child: content)
            : Row(
                children: [
                  _GlassRail(size: size, index: index, onSelected: goTo),
                  Expanded(child: SafeArea(left: false, child: content)),
                ],
              ),
        bottomNavigationBar: size.isCompact
            ? GlassBar(
                child: NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: goTo,
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: PhosphorIcon(d.icon),
                        selectedIcon: PhosphorIcon(d.selected),
                        label: d.label,
                      ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

/// The navigation rail of tablets and large windows. Expanded windows get
/// labels beside the icons and the app's name at the top.
class _GlassRail extends StatelessWidget {
  const _GlassRail({required this.size, required this.index, required this.onSelected});

  final WindowSize size;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final extended = size.isExpanded;
    final short = WindowSize.isShort(context);
    return GlassBar(
      vertical: true,
      child: SafeArea(
        right: false,
        // On a short window (a phone in landscape) the rail scrolls rather than
        // overflows. The rail needs a height, so it gets at least the viewport's.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: onSelected,
                  extended: extended,
                  minExtendedWidth: 232,
                  labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  groupAlignment: -1,
                  leading: Padding(
                    padding: EdgeInsets.symmetric(vertical: short ? 8 : 16),
                    child: extended
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIcon(size: 36),
                              const SizedBox(width: 12),
                              Text(
                                'Flutter Counter',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          )
                        : const AppIcon(size: 40),
                  ),
                  destinations: [
                    for (final d in _HomeShellState.destinations)
                      NavigationRailDestination(
                        icon: PhosphorIcon(d.icon),
                        selectedIcon: PhosphorIcon(d.selected),
                        label: Text(d.label),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The strip above every screen: the app's name (on phones and tablets) and
/// the network picker.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.size});

  final WindowSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // Tiny phones keep the icon and drop the name, so the network chip fits.
    final showTitle = !size.isExpanded && width >= 360;
    return Padding(
      padding: EdgeInsets.fromLTRB(size.isCompact ? 16 : 24, WindowSize.isShort(context) ? 4 : 12, 16, 4),
      child: Row(
        children: [
          if (size.isCompact) ...[const AppIcon(size: 28), const SizedBox(width: 10)],
          Expanded(
            child: showTitle
                ? Text(
                    'Flutter Counter',
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox.shrink(),
          ),
          const NetworkPickerButton(),
        ],
      ),
    );
  }
}
