import 'package:flutter/material.dart';

import '../chains/networks.dart';
import '../state/app_state.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/network_picker.dart';
import 'home_shell.dart';

/// Appearance, which backend verifies signatures, and the status of every
/// network's RPC endpoints.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return ScreenList(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Appearance', icon: Icons.palette_outlined),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (s) => state.themeMode = s.first,
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Backend', icon: Icons.dns_outlined),
              const Text('Where signed messages are verified.'),
              const SizedBox(height: 12),
              SegmentedButton<BackendMode>(
                segments: [for (final mode in BackendMode.values) ButtonSegment(value: mode, label: Text(mode.label))],
                selected: {state.backendMode},
                onSelectionChanged: (s) => state.backendMode = s.first,
              ),
              if (state.backendMode == BackendMode.http) ...[
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: state.serverUrl,
                  decoration: const InputDecoration(labelText: 'Server URL', border: OutlineInputBorder()),
                  onFieldSubmitted: (v) => state.serverUrl = v.trim(),
                ),
                const SizedBox(height: 8),
                Text('Start it with: cd server && dart run bin/server.dart', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Network status', icon: Icons.lan_outlined),
              const Text(
                'The free RPC endpoints the app uses, in the order it tries them. Live health checks arrive in M5.',
              ),
              const SizedBox(height: 8),
              for (final network in Networks.all)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: NetworkDot(network, size: 12),
                  title: Text(network.name),
                  subtitle: Text(
                    '${network.rpcUrls.length} endpoint${network.rpcUrls.length == 1 ? '' : 's'} · active: ${Uri.parse(network.rpcUrls.first).host}',
                  ),
                  children: [
                    for (final (i, url) in network.rpcUrls.indexed)
                      ListTile(
                        dense: true,
                        leading: Icon(i == 0 ? Icons.check_circle : Icons.circle_outlined, size: 18),
                        title: Text(Uri.parse(url).host),
                        subtitle: Text(url),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
