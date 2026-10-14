import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../chains/counter_reader.dart';
import '../../chains/faucets.dart';
import '../../chains/networks.dart';
import '../../screens/wallet_setup_screen.dart';
import '../../state/app_state.dart';
import '../../wallet/hd_keys.dart';
import '../../wallet/signing_explainer.dart';
import '../../wallet/vault.dart';
import '../theme.dart';
import 'glass.dart';
import 'network_picker.dart';
import 'shimmer.dart';
import 'whats_happening.dart';

/// Branch A, "be the wallet": create, import, unlock and use the in-app
/// wallet. [onSteps] receives "What's happening" steps for the screen.
class InAppWalletCard extends StatefulWidget {
  const InAppWalletCard({super.key, required this.onSteps});

  final ValueChanged<List<HappeningStep>> onSteps;

  @override
  State<InAppWalletCard> createState() => _InAppWalletCardState();
}

class _InAppWalletCardState extends State<InAppWalletCard> {
  final password = TextEditingController();
  String? unlockError;
  bool busy = false;

  Future<BigInt>? balance;
  String? balanceFor;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> unlock() async {
    setState(() {
      busy = true;
      unlockError = null;
    });
    try {
      await AppScope.of(context).wallet.unlock(password: password.text);
      password.clear();
    } on WrongPasswordException {
      setState(() => unlockError = 'Wrong password.');
    } on UnlockCancelledException {
      setState(() => unlockError = 'Unlock cancelled.');
    } catch (e) {
      setState(() => unlockError = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final wallet = state.wallet;
    return GlassCard(
      accent: wallet.status == WalletStatus.unlocked ? accentOf(state.network) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(
            title: '1. Be the wallet',
            icon: Icons.shield_outlined,
            trailing: wallet.status == WalletStatus.unlocked ? _menu(context) : null,
          ),
          ...switch (wallet.status) {
            WalletStatus.loading => [const Shimmer(height: 48)],
            WalletStatus.none => _none(context),
            WalletStatus.locked => _locked(context),
            WalletStatus.unlocked => _unlocked(context),
          },
        ],
      ),
    );
  }

  List<Widget> _none(BuildContext context) => [
    const Text(
      'Create or import a 12-word recovery phrase. The app derives a key for every chain, stores the '
      'phrase securely on this device, and signs by itself. Works on every platform.',
    ),
    const SizedBox(height: 16),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => WalletSetupScreen.open(context, SetupMode.create),
          icon: const Icon(Icons.add),
          label: const Text('Create a wallet'),
        ),
        OutlinedButton.icon(
          onPressed: () => WalletSetupScreen.open(context, SetupMode.import),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Import a phrase'),
        ),
      ],
    ),
  ];

  List<Widget> _locked(BuildContext context) {
    final vault = AppScope.of(context).wallet.vault;
    return [
      Text('Your wallet is locked. It is saved in ${vault.storageName}.'),
      const SizedBox(height: 12),
      if (vault.usesPassword) ...[
        TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            errorText: unlockError,
          ),
          onSubmitted: (_) => unlock(),
        ),
        const SizedBox(height: 12),
      ] else if (unlockError != null)
        Text(unlockError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      Row(
        children: [
          FilledButton.icon(
            onPressed: busy ? null : unlock,
            icon: const Icon(Icons.lock_open),
            label: const Text('Unlock'),
          ),
          const Spacer(),
          TextButton(onPressed: () => _remove(context), child: const Text('Remove wallet')),
        ],
      ),
    ];
  }

  List<Widget> _unlocked(BuildContext context) {
    final state = AppScope.of(context);
    final network = state.network;
    final key = state.wallet.keyFor(network.family)!;
    final theme = Theme.of(context);

    // Reload the balance when the network or account changes.
    final id = '${network.id}:${key.address}';
    if (balanceFor != id) {
      balanceFor = id;
      balance = state.services.reader(network).balance(key.address);
    }

    return [
      Row(
        children: [
          NetworkDot(network, size: 10),
          const SizedBox(width: 8),
          Text('Your ${network.family.label} account', style: theme.textTheme.labelLarge),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(child: SelectableText(key.address, style: monoStyle(context, size: 13))),
          IconButton(
            tooltip: 'Copy the address',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key.address));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
            },
          ),
          IconButton(
            tooltip: 'View on the explorer',
            icon: const Icon(Icons.open_in_new, size: 18),
            onPressed: () => launchUrl(Uri.parse(network.addressUrl(key.address))),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FutureBuilder(
        future: balance,
        builder: (context, snapshot) => Row(
          children: [
            Text('Balance', style: theme.textTheme.labelMedium),
            const SizedBox(width: 12),
            if (snapshot.hasData)
              Text(
                '${formatUnits(snapshot.data!, network.decimals)} ${network.symbol}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              )
            else if (snapshot.hasError)
              Text('could not read', style: TextStyle(color: theme.colorScheme.error))
            else
              const Shimmer(width: 80, height: 20),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => setState(() => balanceFor = null),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => _signTest(context),
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Sign a test message'),
          ),
          Faucets.canFundInApp(network)
              ? OutlinedButton.icon(
                  onPressed: busy ? null : () => _fund(context, network, key.address),
                  icon: const Icon(Icons.water_drop_outlined),
                  label: Text('Get ${Faucets.amount(network)}'),
                )
              : OutlinedButton.icon(
                  onPressed: () {
                    // Most faucets ask for the address, so have it ready to paste.
                    Clipboard.setData(ClipboardData(text: key.address));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Address copied. Paste it into the faucet.')));
                    launchUrl(Uri.parse(network.faucetUrl));
                  },
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Open a faucet'),
                ),
        ],
      ),
      const SizedBox(height: 8),
      _AllAddresses(wallet: state.wallet),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Testnet demo. The keys live in this app: never put real funds in it.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _menu(BuildContext context) {
    final wallet = AppScope.of(context).wallet;
    return PopupMenuButton<String>(
      tooltip: 'Wallet options',
      onSelected: (value) => switch (value) {
        'lock' => wallet.lock(),
        'reveal' => _reveal(context),
        _ => _remove(context),
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'lock',
          child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Lock')),
        ),
        PopupMenuItem(
          value: 'reveal',
          child: ListTile(leading: Icon(Icons.visibility_outlined), title: Text('Show recovery phrase')),
        ),
        PopupMenuItem(
          value: 'remove',
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Remove wallet')),
        ),
      ],
    );
  }

  Future<void> _signTest(BuildContext context) async {
    final state = AppScope.of(context);
    final family = state.network.family;
    final signer = state.wallet.signerFor(family)!;
    final message = 'Hello from Flutter Counter!\nTime: ${DateTime.now().toUtc().toIso8601String()}';
    final signed = await signer.signMessage(message);
    widget.onSteps([
      HappeningStep(
        title: 'The message',
        detail: 'Plain text. In M7, the backend writes it and checks the signature.',
        code: message,
        status: StepStatus.done,
      ),
      ...explainSigning(signed, path: HdKeys.paths[family]),
    ]);
  }

  Future<void> _fund(BuildContext context, Network network, String address) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final result = await Faucets.fund(network, address);
      widget.onSteps([
        HappeningStep(
          title: 'Asked the faucet for test tokens',
          detail: result.message,
          link: result.txId == null ? null : Uri.parse(network.txUrl(result.txId!)),
          code: result.txId,
          status: StepStatus.done,
        ),
      ]);
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      // Give the faucet a moment, then read the balance again.
      await Future<void>.delayed(const Duration(seconds: 4));
      if (mounted) setState(() => balanceFor = null);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('The faucet said no: $e'),
          action: SnackBarAction(label: 'Open faucet site', onPressed: () => launchUrl(Uri.parse(network.faucetUrl))),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reveal(BuildContext context) async {
    final wallet = AppScope.of(context).wallet;
    String? pw;
    if (wallet.vault.usesPassword) {
      pw = await _askPassword(context);
      if (pw == null) return;
    }
    try {
      final phrase = await wallet.revealPhrase(password: pw);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery phrase'),
          content: SizedBox(width: 480, child: PhraseGrid(words: phrase.split(' '))),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
        ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _askPassword(BuildContext context) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter your password'),
        content: TextField(
          controller: field,
          obscureText: true,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, field.text), child: const Text('Show')),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final wallet = AppScope.of(context).wallet;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the wallet?'),
        content: const Text(
          'This deletes the recovery phrase from this device. Without a backup of the 12 words, the '
          'keys and anything on these accounts are gone for good.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) await wallet.remove();
  }
}

/// Every chain's address from the one phrase, with its derivation path.
class _AllAddresses extends StatelessWidget {
  const _AllAddresses({required this.wallet});

  final WalletController wallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Your addresses on every chain'),
      subtitle: const Text('One phrase, five derivation paths'),
      children: [
        for (final family in ChainFamily.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('${family.label}  ·  ${HdKeys.paths[family]}', style: theme.textTheme.labelMedium),
            subtitle: SelectableText(wallet.keyFor(family)!.address, style: monoStyle(context, size: 12)),
          ),
      ],
    );
  }
}
