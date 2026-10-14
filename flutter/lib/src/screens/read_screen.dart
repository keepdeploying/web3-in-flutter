import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chains/counter_reader.dart';
import '../chains/networks.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/shimmer.dart';
import '../ui/widgets/whats_happening.dart';
import 'home_shell.dart';

/// Reads public data from the selected network: the counter's total users
/// and recent activity, plus any account's balance and counter.
///
/// None of this needs a wallet. Blockchain data is public: anyone can read
/// any account, for free, through an RPC endpoint.
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key, required this.onSetUpWallet});

  final VoidCallback onSetUpWallet;

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  Network? network;
  final lookup = TextEditingController();

  int? totalUsers;
  List<CounterActivity>? activity;
  Object? publicError;

  String? account;
  BigInt? balance;
  UserCounter? counter;
  Object? accountError;
  bool accountLoading = false;

  List<HappeningStep> steps = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selected = AppScope.of(context).network;
    if (selected != network) {
      network = selected;
      lookup.clear();
      account = null;
      balance = null;
      counter = null;
      accountError = null;
      loadPublic();
    }
  }

  @override
  void dispose() {
    lookup.dispose();
    super.dispose();
  }

  CounterReader get reader => AppScope.of(context).services.reader(network!);

  /// Runs one read and records it as a step in the "What's happening" card:
  /// what was asked, which endpoint answered and how long it took.
  Future<T> step<T>(String title, String explanation, Future<T> Function() read) async {
    final pool = AppScope.of(context).services.pool(network!);
    final started = HappeningStep(title: title, detail: explanation, status: StepStatus.active);
    setState(() => steps = [...steps, started]);
    final watch = Stopwatch()..start();
    try {
      final result = await read();
      final host = pool.lastUsed?.host;
      _replaceStep(
        started,
        started.copyWith(
          status: StepStatus.done,
          detail: '$explanation\nAnswered by $host in ${watch.elapsedMilliseconds} ms.',
        ),
      );
      return result;
    } catch (e) {
      _replaceStep(started, started.copyWith(status: StepStatus.failed, detail: '$explanation\nFailed: $e'));
      rethrow;
    }
  }

  /// Swaps one step for its finished version. Steps from an older load,
  /// already cleared, are ignored.
  void _replaceStep(HappeningStep old, HappeningStep updated) {
    if (!mounted) return;
    setState(() => steps = [for (final s in steps) identical(s, old) ? updated : s]);
  }

  Future<void> loadPublic() async {
    final current = network!;
    setState(() {
      totalUsers = null;
      activity = null;
      publicError = null;
      steps = [];
    });
    try {
      final results = await Future.wait([
        step('Read total users', reader.howTotalUsersIsRead, reader.totalUsers),
        step('Read recent activity', reader.howActivityIsRead, reader.recentActivity),
      ]);
      if (!mounted || current != network) return;
      setState(() {
        totalUsers = results[0] as int;
        activity = results[1] as List<CounterActivity>;
      });
    } catch (e) {
      if (mounted && current == network) setState(() => publicError = e);
    }
  }

  Future<void> loadAccount(String address) async {
    final value = address.trim();
    if (!reader.isValidAddress(value)) {
      setState(() => accountError = 'That is not a valid ${network!.family.label} address.');
      return;
    }
    lookup.text = value;
    final current = network!;
    setState(() {
      account = value;
      accountLoading = true;
      accountError = null;
    });
    try {
      final results = await Future.wait([
        step(
          'Read the balance',
          'The native ${network!.symbol} balance of ${shortAddress(value)}.',
          () => reader.balance(value),
        ),
        step(
          "Read the account's counter",
          'The counter value stored for ${shortAddress(value)}.',
          () => reader.userCounter(value),
        ),
      ]);
      if (!mounted || current != network) return;
      setState(() {
        balance = results[0] as BigInt;
        counter = results[1] as UserCounter;
      });
    } catch (e) {
      if (mounted) setState(() => accountError = e);
    } finally {
      if (mounted) setState(() => accountLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = AppScope.of(context).network;
    final accent = accentOf(network);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await loadPublic();
        if (account != null) await loadAccount(account!);
      },
      child: ScreenList(
        children: [
          GlassCard(
            accent: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardHeader(title: 'Look up an account', icon: Icons.account_balance_wallet_outlined),
                Text(
                  'Reading needs no wallet: paste any ${network.family.label} address, or tap someone in the activity below.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lookup,
                  style: monoStyle(context, size: 13),
                  decoration: InputDecoration(
                    hintText: _hint(network),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Look up',
                      icon: const Icon(Icons.search),
                      onPressed: () => loadAccount(lookup.text),
                    ),
                  ),
                  onSubmitted: loadAccount,
                ),
                if (accountError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$accountError', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                if (account != null && accountError == null) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _Stat(
                        label: 'Balance',
                        value: balance == null ? null : '${formatUnits(balance!, network.decimals)} ${network.symbol}',
                      ),
                      _Stat(
                        label: 'Their counter',
                        value: counter == null ? null : '${counter!.value}${counter!.isUser ? '' : ' (never used)'}',
                      ),
                    ],
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => launchUrl(Uri.parse(network.addressUrl(account!))),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('View the account on the explorer'),
                  ),
                ],
                const SizedBox(height: 4),
                if (AppScope.of(context).wallet.keyFor(network.family) case final key?)
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => loadAccount(key.address),
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: const Text('Look up my account'),
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: widget.onSetUpWallet,
                    icon: const Icon(Icons.key, size: 16),
                    label: const Text('Or set up your own wallet'),
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
                if (publicError != null)
                  _ErrorRow(error: publicError!, onRetry: loadPublic)
                else
                  Wrap(
                    spacing: 32,
                    runSpacing: 16,
                    children: [
                      _Stat(label: 'Total users', value: totalUsers?.toString()),
                      _Stat(label: 'Last change', value: activity == null ? null : _lastChange()),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('Contract', style: theme.textTheme.labelMedium),
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
                if (activity == null && publicError == null)
                  for (var i = 0; i < 3; i++) const _ActivityRow.loading()
                else if (activity != null && activity!.isEmpty)
                  const Text('No counter changes found recently. Be the first in the Write tab.')
                else if (activity != null)
                  for (final a in activity!)
                    _ActivityRow(
                      activity: a,
                      onTap: () => loadAccount(a.user),
                      onOpenTx: () => launchUrl(Uri.parse(network.txUrl(a.txId))),
                    ),
              ],
            ),
          ),
          WhatsHappeningCard(steps: steps),
        ],
      ),
    );
  }

  String _lastChange() => activity!.isEmpty ? 'none yet' : timeAgo(activity!.first.time);

  static String _hint(Network network) => switch (network.family.name) {
    'evm' => '0x... (20 bytes)',
    'solana' => 'Base58 address',
    'sui' => '0x... (32 bytes)',
    'cosmos' => 'osmo1...',
    _ => 'name.testnet or a 64-character implicit account',
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
            ? const Shimmer(width: 96, height: 32)
            : Text(value!, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text('Could not read the network: $error')),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity, this.onTap, this.onOpenTx});
  const _ActivityRow.loading() : activity = null, onTap = null, onOpenTx = null;

  final CounterActivity? activity;
  final VoidCallback? onTap;
  final VoidCallback? onOpenTx;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = Theme.of(context);
    if (a == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Shimmer(width: 36, height: 36, radius: 18),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Shimmer(width: 160), SizedBox(height: 6), Shimmer(width: 100, height: 12)],
            ),
          ],
        ),
      );
    }
    final icon = switch (a.action) {
      CounterAction.increment => Icons.add,
      CounterAction.decrement => Icons.remove,
      CounterAction.reset => Icons.restart_alt,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${shortAddress(a.user)} ${a.action.pastTense}', style: theme.textTheme.bodyLarge),
                  Text('${a.oldValue} → ${a.newValue} · ${timeAgo(a.time)}', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'View the transaction',
              icon: const Icon(Icons.open_in_new, size: 18),
              onPressed: onOpenTx,
            ),
          ],
        ),
      ),
    );
  }
}
