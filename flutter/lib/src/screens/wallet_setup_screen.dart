import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../ui/theme.dart';
import '../ui/widgets/glass.dart';
import '../wallet/hd_keys.dart';
import '../wallet/vault.dart';

enum SetupMode { create, import }

enum _Step { phrase, quiz, import, protect }

/// Creates or imports a recovery phrase, checks the backup, and chooses how
/// the phrase is protected on this device.
class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key, required this.mode});

  final SetupMode mode;

  static Future<void> open(BuildContext context, SetupMode mode) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => WalletSetupScreen(mode: mode)));

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  late _Step step = widget.mode == SetupMode.create ? _Step.phrase : _Step.import;
  late String phrase = widget.mode == SetupMode.create ? HdKeys.generateMnemonic() : '';
  bool savedIt = false;

  // Quiz: three positions to confirm, and the word picked for each.
  late final List<int> quizPositions = (List.generate(12, (i) => i)..shuffle(Random.secure())).take(3).toList()..sort();
  final Map<int, String> answers = {};

  final importField = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool stayUnlocked = false;
  bool requireDeviceAuth = true;
  bool? deviceAuthAvailable;
  bool saving = false;
  String? error;

  List<String> get words => phrase.split(' ');

  @override
  void initState() {
    super.initState();
    importField.addListener(() => setState(() {}));
    password.addListener(() => setState(() {}));
    confirm.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    deviceAuthAvailable ??= false;
    AppScope.of(context).wallet.vault.canUseDeviceAuth().then((ok) {
      if (mounted) setState(() => deviceAuthAvailable = ok);
    });
  }

  @override
  void dispose() {
    importField.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> finish() async {
    final wallet = AppScope.of(context).wallet;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await wallet.save(
        phrase,
        VaultOptions(
          password: wallet.vault.usesPassword ? password.text : null,
          stayUnlocked: stayUnlocked,
          requireDeviceAuth: !wallet.vault.usesPassword && requireDeviceAuth && deviceAuthAvailable == true,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> keepInMemory() async {
    await AppScope.of(context).wallet.saveInMemory(phrase);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final title = widget.mode == SetupMode.create ? 'Create a wallet' : 'Import a wallet';
    return GlassBackground(
      accent: accentOf(state.network),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: GlassCard(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: switch (step) {
                      _Step.phrase => _phraseStep(context),
                      _Step.quiz => _quizStep(context),
                      _Step.import => _importStep(context),
                      _Step.protect => _protectStep(context),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phraseStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardHeader(title: 'Your recovery phrase', icon: Icons.key),
        const Text(
          'These 12 words are your wallet. Every key on every chain is derived from them, so anyone '
          'who has them controls the wallet, and if you lose them, nobody can get it back.',
        ),
        const SizedBox(height: 16),
        PhraseGrid(words: words),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => phrase = HdKeys.generateMnemonic()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('New words'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: phrase)),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
          ],
        ),
        Text(
          'A real wallet would block copying and screenshots here. This is a testnet demo, so copying '
          'is allowed to make testing easier.',
          style: theme.textTheme.bodySmall,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: savedIt,
          onChanged: (v) => setState(() => savedIt = v ?? false),
          title: const Text('I wrote these words down'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: savedIt ? () => setState(() => step = _Step.quiz) : null,
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _quizStep(BuildContext context) {
    final theme = Theme.of(context);
    final allCorrect = quizPositions.every((i) => answers[i] == words[i]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardHeader(title: 'Check your backup', icon: Icons.fact_check_outlined),
        const Text('Pick the right word for each position. Wallets ask this so nobody skips the backup.'),
        for (final position in quizPositions) ...[
          const SizedBox(height: 16),
          Text('Word #${position + 1}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _options(position))
                ChoiceChip(
                  key: Key('quiz-$position-$option'),
                  label: Text(option, style: monoStyle(context, size: 13)),
                  selected: answers[position] == option,
                  onSelected: (_) => setState(() => answers[position] = option),
                ),
            ],
          ),
          if (answers[position] != null && answers[position] != words[position])
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Not that one.', style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            TextButton(onPressed: () => setState(() => step = _Step.phrase), child: const Text('Show the words again')),
            const Spacer(),
            FilledButton(
              onPressed: allCorrect ? () => setState(() => step = _Step.protect) : null,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }

  /// The right word and three others from the phrase, in a stable shuffle.
  List<String> _options(int position) {
    final others = {...words}..remove(words[position]);
    final picked = (others.toList()..shuffle(Random(position * 31 + phrase.length))).take(3);
    return [words[position], ...picked]..shuffle(Random(position));
  }

  Widget _importStep(BuildContext context) {
    final text = importField.text;
    final count = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final valid = HdKeys.isValidMnemonic(text);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardHeader(title: 'Enter a recovery phrase', icon: Icons.download_outlined),
        const Text(
          'Paste or type 12 or 24 words from MetaMask, Phantom, Slush, Keplr or a NEAR wallet. The '
          'app derives the same addresses those wallets show. Use a testnet-only phrase.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: importField,
          minLines: 3,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          style: monoStyle(context, size: 14),
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'word1 word2 word3 ...'),
        ),
        const SizedBox(height: 8),
        Text(
          count == 0
              ? 'Words are checked against the BIP-39 list, and the last word holds a checksum.'
              : valid
              ? '$count words, checksum OK.'
              : '$count words. Not valid yet: check the spelling and the order.',
          style: theme.textTheme.bodySmall?.copyWith(color: count > 0 && !valid ? theme.colorScheme.error : null),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: valid
                ? () => setState(() {
                    phrase = HdKeys.normalize(text);
                    step = _Step.protect;
                  })
                : null,
            child: const Text('Next'),
          ),
        ),
      ],
    );
  }

  Widget _protectStep(BuildContext context) {
    final vault = AppScope.of(context).wallet.vault;
    final theme = Theme.of(context);
    final inMemory = AppScope.of(context).wallet.vaultProblem != null;
    final passwordOk = password.text.length >= 8 && password.text == confirm.text;
    final canFinish = !saving && (!vault.usesPassword || passwordOk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardHeader(title: 'Protect it on this device', icon: Icons.lock_outline),
        Text('The phrase will be saved in ${vault.storageName}.'),
        if (inMemory) ...[
          const SizedBox(height: 8),
          Text(
            "This device's secure storage isn't available, so the wallet stays in memory until the app "
            'closes. On Linux, a running keyring (GNOME Keyring or KWallet) fixes this.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (vault.usesPassword) ...[
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password (8 characters or more)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirm,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Repeat the password',
              border: const OutlineInputBorder(),
              errorText: confirm.text.isNotEmpty && confirm.text != password.text ? "Passwords don't match" : null,
            ),
            onSubmitted: (_) => canFinish ? finish() : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Your password turns into an encryption key with PBKDF2 (600,000 rounds), and AES-GCM '
            'encrypts the phrase. Neither the password nor the key is stored.',
            style: theme.textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: stayUnlocked,
            onChanged: (v) => setState(() => stayUnlocked = v),
            title: const Text('Stay unlocked in this browser'),
            subtitle: const Text(
              'Keeps a second copy, encrypted with a key the browser never lets anyone read. '
              'Reloading the page then skips the password, until you lock the wallet.',
            ),
          ),
        ] else if (!inMemory)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: requireDeviceAuth && deviceAuthAvailable == true,
            onChanged: deviceAuthAvailable == true ? (v) => setState(() => requireDeviceAuth = v) : null,
            title: const Text('Ask for my fingerprint, face or PIN to unlock'),
            subtitle: Text(
              deviceAuthAvailable == true
                  ? 'Uses local_auth before the app reads the phrase.'
                  : 'Not available on this device. The system keyring still protects the phrase.',
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text('Could not save: $error', style: TextStyle(color: theme.colorScheme.error)),
          TextButton(onPressed: keepInMemory, child: const Text('Keep it in memory only (gone when the app closes)')),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: canFinish ? finish : null,
            icon: saving
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save the wallet'),
          ),
        ),
      ],
    );
  }
}

/// The recovery phrase as numbered words, three or four columns wide.
class PhraseGrid extends StatelessWidget {
  const PhraseGrid({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 480 ? 4 : 3;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, word) in words.indexed)
              Container(
                width: width,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: theme.textTheme.bodySmall)),
                    Expanded(
                      child: Text(
                        word,
                        key: Key('phrase-word-$i'),
                        style: monoStyle(context, size: 14, weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
