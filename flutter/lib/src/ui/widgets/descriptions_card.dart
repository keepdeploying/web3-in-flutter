import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../backend/backend.dart';
import '../../chains/chain_family.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'glass.dart';

/// The protected endpoint of the demo: a signed-in account can save one
/// short description, and everyone can read the list.
class DescriptionsCard extends StatefulWidget {
  const DescriptionsCard({super.key});

  @override
  State<DescriptionsCard> createState() => _DescriptionsCardState();
}

class _DescriptionsCardState extends State<DescriptionsCard> {
  final field = TextEditingController();
  String? error;
  Backend? loadedFrom;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load the list once per backend.
    final backend = AppScope.of(context).backend;
    if (!identical(backend, loadedFrom)) {
      loadedFrom = backend;
      // After this frame: loading notifies listeners, which can't happen
      // while widgets are building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppScope.of(context).session.loadDescriptions(backend).catchError((Object e) {
          if (mounted) setState(() => error = 'Could not load descriptions: $e');
        });
      });
    }
  }

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final state = AppScope.of(context);
    setState(() => error = null);
    try {
      await state.session.saveDescription(state.backend, field.text);
      field.clear();
    } on UnauthorizedException catch (e) {
      setState(() => error = '${e.message} The backend refused: no valid session.');
    } on ArgumentError catch (e) {
      setState(() => error = '${e.message}');
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.session;
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(
            title: 'Descriptions',
            icon: PhosphorIconsDuotone.chatText,
            trailing: IconButton(
              tooltip: 'Refresh',
              icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 20),
              onPressed: session.busy ? null : () => session.loadDescriptions(state.backend),
            ),
          ),
          const Text(
            'A protected endpoint: only a signed-in account can save its line, because the backend checks the '
            'session token. Anyone can read the list.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: field,
            enabled: session.signedIn && !session.busy,
            maxLength: 140,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: session.signedIn ? 'Say something about this wallet' : 'Sign in to write yours',
              errorText: error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => save(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: session.signedIn && !session.busy ? save : null,
              icon: const Icon(PhosphorIconsRegular.floppyDisk, size: 18),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(height: 8),
          if (session.descriptions.isEmpty)
            Text('No descriptions yet. Be the first.', style: theme.textTheme.bodySmall)
          else
            for (final d in session.descriptions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconTile(icon: PhosphorIconsDuotone.userCircle, size: 36, iconSize: 20, circle: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.text, style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 2),
                          Text(
                            '${_familyLabel(d.family)} · ${shortAddress(d.address)} · ${timeAgo(d.updatedAt)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _familyLabel(String name) => ChainFamily.values.where((f) => f.name == name).firstOrNull?.label ?? name;
}
