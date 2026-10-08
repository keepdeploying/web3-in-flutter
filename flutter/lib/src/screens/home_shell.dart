import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/network_picker.dart';
import 'auth_screen.dart';
import 'read_screen.dart';
import 'settings_screen.dart';
import 'write_screen.dart';

/// The app's frame: the background, the top bar with the network picker, and
/// navigation between the four screens.
///
/// On phones the navigation is a bar at the bottom. On wide screens (tablets,
/// desktop and the web) it moves to a rail on the left, so the content can
/// use the width.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const destinations = [
    (icon: Icons.travel_explore_outlined, selected: Icons.travel_explore, label: 'Read'),
    (icon: Icons.key_outlined, selected: Icons.key, label: 'Sign in'),
    (icon: Icons.edit_note_outlined, selected: Icons.edit_note, label: 'Write'),
    (icon: Icons.tune_outlined, selected: Icons.tune, label: 'Settings'),
  ];

  void goTo(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    final screen = switch (index) {
      0 => ReadScreen(onSetUpWallet: () => goTo(1)),
      1 => const AuthScreen(),
      2 => WriteScreen(onSetUpWallet: () => goTo(1)),
      _ => const SettingsScreen(),
    };

    final body = SafeArea(
      bottom: false,
      child: Column(
        children: [
          _TopBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(key: ValueKey(index), child: screen),
            ),
          ),
        ],
      ),
    );

    return GlassBackground(
      accent: accentOf(state.network),
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: goTo,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selected),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              )
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: goTo,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
                ],
              ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Flutter Counter',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const NetworkPickerButton(),
        ],
      ),
    );
  }
}

/// The scrollable, width-limited column every screen puts its cards in.
class ScreenList extends StatelessWidget {
  const ScreenList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(height: 16), child],
              ],
            ),
          ),
        ),
      ],
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
          Icon(Icons.science_outlined, color: scheme.tertiary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Design preview: the numbers on this screen are placeholders.')),
        ],
      ),
    );
  }
}
