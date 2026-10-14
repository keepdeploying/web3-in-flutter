import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../chains/networks.dart';
import '../rpc/rpc_pool.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/network_logo.dart';
import '../ui/widgets/screen_layout.dart';

/// Appearance, which backend verifies signatures, and the status of every
/// network's RPC endpoints.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return ScreenLayout(
      title: 'Settings',
      subtitle: 'Appearance, the backend, and the health of every RPC endpoint.',
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Appearance', icon: PhosphorIconsDuotone.palette),
              // Icons only when there is room, so the labels never wrap. If even the
              // labels do not fit (large text), the buttons scroll sideways.
              LayoutBuilder(
                builder: (context, constraints) {
                  final withIcons = constraints.maxWidth >= 400;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<ThemeMode>(
                      // The fill already shows the selection, and a tick would not fit on a phone.
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: withIcons ? PhosphorIcon(PhosphorIconsRegular.circleHalf, size: 18) : null,
                          label: const Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: withIcons ? PhosphorIcon(PhosphorIconsRegular.sun, size: 18) : null,
                          label: const Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: withIcons ? PhosphorIcon(PhosphorIconsRegular.moon, size: 18) : null,
                          label: const Text('Dark'),
                        ),
                      ],
                      selected: {state.themeMode},
                      onSelectionChanged: (s) => state.themeMode = s.first,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardHeader(title: 'Backend', icon: PhosphorIconsDuotone.hardDrives),
              const Text('Where signed messages are verified.'),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<BackendMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final mode in BackendMode.values) ButtonSegment(value: mode, label: Text(mode.shortLabel)),
                  ],
                  selected: {state.backendMode},
                  onSelectionChanged: (s) => state.backendMode = s.first,
                ),
              ),
              const SizedBox(height: 8),
              Text(state.backendMode.description, style: theme.textTheme.bodySmall),
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
        const NetworkStatusCard(),
      ],
    );
  }
}

/// Every network's RPC endpoints, live: which one is in use, how fast each
/// answered, which are resting after failures, and a log of switches.
class NetworkStatusCard extends StatefulWidget {
  const NetworkStatusCard({super.key});

  @override
  State<NetworkStatusCard> createState() => _NetworkStatusCardState();
}

class _NetworkStatusCardState extends State<NetworkStatusCard> {
  bool checking = false;

  Future<void> checkAll() async {
    final services = AppScope.of(context).services;
    setState(() => checking = true);
    await Future.wait([for (final network in Networks.all) services.reader(network).checkEndpoints()]);
    if (mounted) setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context).services;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(
            title: 'Network status',
            icon: PhosphorIconsDuotone.broadcast,
            trailing: checking
                // The same 48 px as the button, so the header doesn't jump.
                ? const SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                : IconButton(
                    tooltip: 'Check all endpoints',
                    icon: PhosphorIcon(PhosphorIconsRegular.arrowClockwise, size: 20),
                    onPressed: checkAll,
                  ),
          ),
          const Text(
            'The free RPC endpoints the app uses, in the order it tries them. When one fails, times out or rate '
            'limits, the app rests it and moves to the next one.',
          ),
          const SizedBox(height: 8),
          for (final network in Networks.all) _NetworkTile(network: network, pool: services.pool(network)),
        ],
      ),
    );
  }
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network, required this.pool});

  final Network network;
  final RpcPool pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: pool.changes,
      builder: (context, _) {
        final now = DateTime.now();
        final active = pool.active;
        final resting = pool.endpoints.where((e) => e.isCoolingDown(now)).length;
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: NetworkLogo(network, size: 28),
          title: Text(network.name),
          subtitle: Text(
            'Using ${active.host}'
            '${active.lastLatency == null ? '' : ' (${active.lastLatency!.inMilliseconds} ms)'}'
            '${resting == 0 ? '' : ' · $resting resting'}',
          ),
          children: [
            for (final endpoint in pool.endpoints) _EndpointRow(endpoint: endpoint, active: endpoint == active),
            if (pool.log.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Switch log', style: theme.textTheme.labelMedium),
              ),
              for (final event in pool.log.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 72, child: Text(timeAgo(event.time), style: theme.textTheme.bodySmall)),
                      Expanded(child: Text(event.message, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.endpoint, required this.active});

  final EndpointStatus endpoint;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final resting = endpoint.isCoolingDown(now);
    final (icon, color) = switch ((active, resting, endpoint.lastSuccess != null)) {
      (true, _, _) => (PhosphorIconsFill.checkCircle, scheme.primary),
      (_, true, _) => (PhosphorIconsRegular.pauseCircle, scheme.error),
      (_, _, true) => (PhosphorIconsRegular.checkCircle, Colors.green.shade600),
      _ => (PhosphorIconsRegular.circle, scheme.outline),
    };
    final details = [
      if (endpoint.lastLatency != null) '${endpoint.lastLatency!.inMilliseconds} ms',
      if (resting) 'resting ${endpoint.cooldownUntil!.difference(now).inSeconds} s more',
      if (endpoint.lastError != null) endpoint.lastError!,
      if (endpoint.lastLatency == null && endpoint.lastError == null) 'not tried yet',
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: PhosphorIcon(icon, size: 18, color: color),
      title: Text(endpoint.host),
      subtitle: Text(details.join(' · ')),
    );
  }
}
