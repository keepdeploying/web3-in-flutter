import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chains/chain_family.dart';
import '../chains/networks.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/shimmer.dart';
import '../ui/widgets/whats_happening.dart';
import 'home_shell.dart';

/// Reads public data from the selected network: the counter's totals and
/// recent activity, and (once a wallet is set up) your balance and counter.
///
/// For now (milestone M4) the numbers are placeholders, loaded after a short
/// delay so the loading skeletons show. M5 replaces them with real reads.
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key, required this.onSetUpWallet});

  final VoidCallback onSetUpWallet;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  Network? loadedFor;
  Future<_DemoReads>? reads;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final network = AppScope.of(context).network;
    if (network != loadedFor) {
      loadedFor = network;
      reads = _DemoReads.load(network);
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = AppScope.of(context).network;
    final accent = accentOf(network);

    return FutureBuilder<_DemoReads>(
      future: reads,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return ScreenList(
          children: [
            const DemoBanner(),
            GlassCard(
              accent: accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeader(title: 'Your account', icon: Icons.account_balance_wallet_outlined),
                  const Text('Set up a wallet to see your balance and your own counter on this network.'),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.onSetUpWallet,
                      icon: const Icon(Icons.key),
                      label: const Text('Set up a wallet'),
                    ),
                  ),
                ],
              ),
            ),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardHeader(
                    title: 'The counter on ${network.name}',
                    icon: Icons.exposure,
                    trailing: IconButton(
                      tooltip: 'Open the contract in the explorer',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () => launchUrl(Uri.parse(network.addressUrl(network.counter))),
                    ),
                  ),
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _Stat(label: 'Total users', value: data?.totalUsers.toString()),
                      _Stat(label: 'Changes today', value: data?.changesToday.toString()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Contract', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(network.counter, style: monoStyle(context, size: 13)),
                ],
              ),
            ),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CardHeader(title: 'Recent activity', icon: Icons.history),
                  if (data == null)
                    for (var i = 0; i < 4; i++) const _ActivityRow.loading()
                  else
                    for (final activity in data.activity) _ActivityRow(activity: activity),
                ],
              ),
            ),
            WhatsHappeningCard(
              steps: [
                HappeningStep(
                  title: 'Connected to ${Uri.parse(network.rpcUrls.first).host}',
                  detail: 'The first of ${network.rpcUrls.length} free endpoints for ${network.name}.',
                  status: data == null ? StepStatus.active : StepStatus.done,
                ),
                HappeningStep(
                  title: 'Read the counter totals',
                  detail: _readExplanation(network),
                  status: data == null ? StepStatus.pending : StepStatus.done,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _readExplanation(Network network) => switch (network.family) {
    ChainFamily.evm => 'An eth_call to totalUsers() on the counter contract. Reads are free: no wallet, no gas.',
    ChainFamily.solana => 'Fetched the Global account (PDA "global") and decoded its total_users field.',
    ChainFamily.sui => 'Asked Sui GraphQL for the shared Registry object and read total_users.',
    ChainFamily.cosmos => 'A smart query {"total_users":{}} to the CosmWasm contract over the REST API.',
    ChainFamily.near => 'A view call to total_users() on the NEAR contract.',
  };
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        value == null
            ? const Shimmer(width: 64, height: 32)
            : Text(value!, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  const _ActivityRow.loading() : activity = null;

  final _DemoActivity? activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          a == null
              ? const Shimmer(width: 36, height: 36, radius: 18)
              : CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(a.icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: a == null
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Shimmer(width: 160), SizedBox(height: 6), Shimmer(width: 100, height: 12)],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${shortAddress(a.user)} ${a.verb}', style: theme.textTheme.bodyLarge),
                      Text('${a.from} → ${a.to} · ${a.ago}', style: theme.textTheme.bodySmall),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder data for the M4 design preview.
class _DemoReads {
  const _DemoReads({required this.totalUsers, required this.changesToday, required this.activity});

  final int totalUsers;
  final int changesToday;
  final List<_DemoActivity> activity;

  static Future<_DemoReads> load(Network network) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final seed = network.id.length;
    return _DemoReads(
      totalUsers: 3 + seed % 5,
      changesToday: 7 + seed,
      activity: const [
        _DemoActivity('0xfFFAa29e82d5455985a908235536d2cD01aCce47', 'incremented', 4, 5, '2 min ago', Icons.add),
        _DemoActivity('0x9858EfFD232B4033E47d90003D41EC34EcaEda94', 'decremented', 1, 0, '9 min ago', Icons.remove),
        _DemoActivity('0x5e93a736d04fbb25737aa40bee40171ef79f65fa', 'reset', 12, 0, '1 hour ago', Icons.restart_alt),
      ],
    );
  }
}

class _DemoActivity {
  const _DemoActivity(this.user, this.verb, this.from, this.to, this.ago, this.icon);

  final String user;
  final String verb;
  final int from;
  final int to;
  final String ago;
  final IconData icon;
}
