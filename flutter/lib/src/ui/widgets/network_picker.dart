import 'package:flutter/material.dart';

import '../../chains/chain_family.dart';
import '../../chains/networks.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// A colored dot in the network's brand color.
class NetworkDot extends StatelessWidget {
  const NetworkDot(this.network, {super.key, this.size = 10});

  final Network network;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = accentOf(network);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: size)],
      ),
    );
  }
}

/// The button at the top of every screen that shows the selected network and
/// opens the network list.
class NetworkPickerButton extends StatelessWidget {
  const NetworkPickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ActionChip(
      avatar: NetworkDot(state.network),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(state.network.name), const Icon(Icons.expand_more, size: 18)],
      ),
      shape: const StadiumBorder(),
      onPressed: () => showNetworkSheet(context),
    );
  }
}

/// Opens a sheet listing every network, grouped by chain family.
Future<void> showNetworkSheet(BuildContext context) {
  final state = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final family in ChainFamily.values) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(family.label, style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final network in Networks.all.where((n) => n.family == family))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: NetworkDot(network, size: 14),
                title: Text(network.name),
                subtitle: Text('${network.symbol} · ${network.chainId}'),
                trailing: network == state.network ? const Icon(Icons.check) : null,
                onTap: () {
                  state.network = network;
                  Navigator.pop(context);
                },
              ),
          ],
        ],
      ),
    ),
  );
}
