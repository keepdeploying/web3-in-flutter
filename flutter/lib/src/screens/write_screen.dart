import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chains/counter_reader.dart';
import '../chains/counter_writer.dart';
import '../chains/networks.dart';
import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../ui/widgets/screen_layout.dart';
import '../ui/widgets/shimmer.dart';
import '../ui/widgets/whats_happening.dart';
import '../wallet/in_app_signer.dart';
import '../wallet/wallet_signer.dart';

/// Changes your counter on the selected network: increment, decrement or
/// reset. Each one is a transaction your wallet signs and pays a small fee
/// for, built by the chain's [CounterWriter].
class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, required this.onSetUpWallet});

  final VoidCallback onSetUpWallet;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  List<HappeningStep> steps = const [];
  bool busy = false;

  /// The account and network the numbers below belong to.
  String? loadedFor;
  int? value;
  BigInt? balance;
  Object? readError;

  ({Network network, String txId, Duration elapsed})? lastTx;
  String? sendError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final address = state.signer?.address;
    final id = address == null ? null : '${state.network.id}:$address';
    if (id != loadedFor) {
      loadedFor = id;
      // Steps of a transaction on another network or account don't apply.
      if (!busy) steps = const [];
      value = null;
      balance = null;
      readError = null;
      sendError = null;
      if (address != null) unawaited(load(state.network, address));
    }
  }

  Future<void> load(Network network, String address) async {
    final reader = AppScope.of(context).services.reader(network);
    try {
      final results = await Future.wait([reader.userCounter(address), reader.balance(address)]);
      if (!mounted || loadedFor != '${network.id}:$address') return;
      setState(() {
        value = (results[0] as UserCounter).value;
        balance = results[1] as BigInt;
      });
    } catch (e) {
      if (mounted) setState(() => readError = e);
    }
  }

  Future<void> send(CounterAction action) async {
    final state = AppScope.of(context);
    final network = state.network;
    final signer = state.signer;
    if (signer == null) return;
    final writer = CounterWriter.forNetwork(network, state.services.pool(network));
    final reader = state.services.reader(network);
    final before = value;

    setState(() {
      busy = true;
      sendError = null;
      steps = [HappeningStep(title: 'Sending ${action.name} on ${network.name}...', status: StepStatus.active)];
    });
    void add(TxStep step) {
      if (!mounted) return;
      setState(() {
        steps = [
          ...steps.where((s) => s.status != StepStatus.active),
          if (step.waitsForUser)
            HappeningStep(title: step.title, detail: step.detail, status: StepStatus.active)
          else ...[
            HappeningStep(title: step.title, detail: step.detail, code: step.code, status: StepStatus.done),
            const HappeningStep(title: 'Working...', status: StepStatus.active),
          ],
        ];
      });
    }

    try {
      final result = await writer.send(action, signer, onStep: add);
      // Reads can lag a moment behind the node that confirmed the write.
      var now = (await reader.userCounter(signer.address)).value;
      for (var i = 0; i < 5 && now == before && action != CounterAction.reset; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        now = (await reader.userCounter(signer.address)).value;
      }
      final newBalance = await reader.balance(signer.address).catchError((_) => balance ?? BigInt.zero);
      if (!mounted) return;
      setState(() {
        value = now;
        balance = newBalance;
        lastTx = (network: network, txId: result.txId, elapsed: result.elapsed);
        steps = [
          ...steps.where((s) => s.status != StepStatus.active),
          HappeningStep(
            title: 'Read the counter again: $now',
            detail:
                'Confirmed in ${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s'
                '${signer is InAppSigner ? '' : ', counting the time you took to approve'}. Anyone can now read the '
                'new value, as the Read screen does.',
            link: Uri.parse(network.txUrl(result.txId)),
            status: StepStatus.done,
          ),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        sendError = '$e';
        steps = [
          ...steps.where((s) => s.status != StepStatus.active),
          HappeningStep(title: 'It did not go through', detail: '$e', status: StepStatus.failed),
        ];
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final network = state.network;
    final signer = state.signer;

    return ScreenLayout(
      title: 'Change your counter',
      subtitle: 'Each change is a transaction your wallet signs and pays a small fee for.',
      aside: WhatsHappeningCard(steps: steps),
      children: [signer != null ? _counterCard(context, network, signer) : _noWalletCard(context)],
    );
  }

  Widget _noWalletCard(BuildContext context) => GlassCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardHeader(title: 'A wallet signs every change', icon: PhosphorIconsDuotone.wallet),
        const Text(
          'Reading is free and needs no wallet, but changing the counter is a transaction: your key signs it and '
          'your account pays the fee. Unlock the in-app wallet, or connect one you have on the Sign in screen.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.onSetUpWallet,
          icon: const Icon(PhosphorIconsRegular.key, size: 18),
          label: const Text('Set up a wallet'),
        ),
      ],
    ),
  );

  Widget _counterCard(BuildContext context, Network network, WalletSigner signer) {
    final theme = Theme.of(context);
    final accent = accentOf(network);
    final noFunds = balance == BigInt.zero;
    final tx = lastTx?.network == network ? lastTx : null;

    return GlassCard(
      accent: accent,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('Your counter on ${network.name}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (readError != null)
            Text('Could not read it: $readError', style: TextStyle(color: theme.colorScheme.error))
          else if (value == null)
            const Shimmer(width: 96, height: 56)
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              // Scales down instead of overflowing when the number gets long.
              child: FittedBox(
                key: ValueKey(value),
                fit: BoxFit.scaleDown,
                child: Text(
                  '$value',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    // Digits of equal width, so the number doesn't jiggle as it changes.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            balance == null ? ' ' : 'Balance: ${formatUnits(balance!, network.decimals)} ${network.symbol}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => send(CounterAction.increment),
                icon: const PhosphorIcon(PhosphorIconsRegular.plus, size: 18),
                label: const Text('Increment'),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : () => send(CounterAction.decrement),
                icon: const PhosphorIcon(PhosphorIconsRegular.minus, size: 18),
                label: const Text('Decrement'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => send(CounterAction.reset),
                icon: const PhosphorIcon(PhosphorIconsRegular.arrowCounterClockwise, size: 18),
                label: const Text('Reset'),
              ),
            ],
          ),
          if (busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(
              signer is InAppSigner
                  ? 'Building, signing and sending. Follow each step in "What\'s happening".'
                  : 'Approve it in ${signer.name}, then follow each step in "What\'s happening".',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (noFunds && !busy) ...[
            const SizedBox(height: 16),
            Text(
              'This account has no ${network.symbol} for fees yet. Get some from a faucet on the Sign in screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (sendError != null && !busy) ...[
            const SizedBox(height: 16),
            Text(
              sendError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (tx != null && !busy) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(network.txUrl(tx.txId))),
              icon: const Icon(PhosphorIconsRegular.arrowSquareOut, size: 16),
              label: Text(
                'Last transaction ${shortAddress(tx.txId, head: 8, tail: 6)}, '
                '${(tx.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
