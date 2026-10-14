import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../chains/chain_family.dart';
import '../../chains/networks.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import 'network_logo.dart';

/// The button at the top of every screen that shows the selected network and
/// opens the network list.
class NetworkPickerButton extends StatelessWidget {
  const NetworkPickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final network = AppScope.of(context).network;
    final scheme = Theme.of(context).colorScheme;
    final compact = WindowSize.of(context).isCompact;
    return Semantics(
      button: true,
      label: 'Network: ${network.name}',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('network-chip'),
        customBorder: const StadiumBorder(),
        onTap: () => showNetworkPicker(context),
        // The chip looks 36 px tall; the tap area around it is 44.
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 44, maxWidth: compact ? 180 : 260),
          // widthFactor: shrink to the pill, instead of centering it in the full width.
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.surface.withValues(alpha: 0.6),
                shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NetworkLogo(network, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        network.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(width: 4),
                    PhosphorIcon(PhosphorIconsRegular.caretDown, size: 14, color: scheme.onSurfaceVariant),
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

/// Lets tests find the picker's list, which is the only scrollable that matters while it is open.
const networkListKey = Key('network-list');

/// Opens the list of networks: a bottom sheet on phones, a centered dialog
/// on bigger windows. Both stop short of the screen's edges and scroll, so
/// every network stays reachable on a short screen (a phone held sideways).
Future<void> showNetworkPicker(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  if (WindowSize.of(context).isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Without this a sheet is capped at 9/16 of the screen and the list would be cut off.
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: height * 0.85),
      builder: (_) => const _NetworkList(),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: height * 0.8),
        child: const _NetworkList(inDialog: true),
      ),
    ),
  );
}

/// Every network, grouped by chain family. The list scrolls inside whatever height it is given.
class _NetworkList extends StatelessWidget {
  const _NetworkList({this.inDialog = false});

  /// A dialog has no drag handle, so it gets a title and a close button.
  final bool inDialog;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inDialog)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Choose a network', style: theme.textTheme.titleLarge)),
                  IconButton(
                    tooltip: 'Close',
                    icon: PhosphorIcon(PhosphorIconsRegular.x, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          Flexible(
            child: ListView(
              key: networkListKey,
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                for (final family in ChainFamily.values) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                    child: Text(
                      family.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final network in Networks.all.where((n) => n.family == family))
                    _NetworkRow(
                      network: network,
                      selected: network == state.network,
                      onTap: () {
                        state.network = network;
                        Navigator.pop(context);
                      },
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({required this.network, required this.selected, required this.onTap});

  final Network network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selected: selected,
      selectedColor: scheme.onSurface,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
      leading: NetworkLogo(network, size: 32),
      title: Text(network.name, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('${network.symbol} · ${network.chainId}'),
      trailing: selected ? PhosphorIcon(PhosphorIconsFill.checkCircle, color: scheme.primary) : null,
      onTap: onTap,
    );
  }
}
