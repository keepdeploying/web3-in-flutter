import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' show RpcChainLookup, SignatureVerifier;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../chains/networks.dart';
import '../../state/app_state.dart';
import '../../wallet/installed/mobile/wallet_browsers.dart';
import '../../wallet/wallet_signer.dart';
import '../../wallet/signing_explainer.dart';
import '../theme.dart';
import 'address_view.dart';
import 'glass.dart';
import 'whats_happening.dart';

/// Option 2: connect a wallet that is already installed, with no SDK.
///
/// Lists the wallets found for the selected network's chain. Once one is
/// connected, it signs for that chain instead of the in-app wallet.
///
/// With [sdk], the same card is option 3: wallets reached through an SDK
/// (Reown AppKit, near_wallet_connect) instead of found on the device.
class InstalledWalletCard extends StatefulWidget {
  const InstalledWalletCard({super.key, required this.onSteps, this.sdk = false});

  final ValueChanged<List<HappeningStep>> onSteps;
  final bool sdk;

  @override
  State<InstalledWalletCard> createState() => _InstalledWalletCardState();
}

class _InstalledWalletCardState extends State<InstalledWalletCard> {
  /// Wallet browsers only matter in the Android and iOS apps.
  static bool get _onPhone =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  bool signing = false;

  /// Checks test signatures the way the backend would.
  late final verifier = SignatureVerifier(lookup: RpcChainLookup());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final network = state.network;
    final connections = state.connections;
    final sdk = widget.sdk;
    final wallets = sdk ? connections.sdkWalletsFor(network.family) : connections.walletsFor(network.family);
    // Each card shows the connections made from its own wallets.
    final signer = connections.signerFor(network.family);
    final connected = signer != null && wallets.contains(signer.wallet) ? signer : null;
    final mine = wallets.contains(connections.lastAttempt);
    final theme = Theme.of(context);

    return GlassCard(
      accent: connected == null ? null : accentOf(network),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sdk
              ? const CardHeader(title: '3. Use an SDK', icon: PhosphorIconsDuotone.puzzlePiece)
              : const CardHeader(title: '2. Use a wallet you have', icon: PhosphorIconsDuotone.plugsConnected),
          if (connected != null) ...[
            Row(
              children: [
                WalletIcon(connected.wallet.icon, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${connected.name}, connected through ${connected.wallet.via}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AddressView(address: connected.address, network: network),
            const SizedBox(height: 4),
            Text(
              'It signs for ${network.family.label} instead of the in-app wallet. Each signature and transaction '
              'opens ${connected.name} for you to approve.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: signing ? null : () => _signTest(connected, network),
                  icon: signing
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const PhosphorIcon(PhosphorIconsRegular.signature, size: 18),
                  label: Text(signing ? 'Approve it in ${connected.name}...' : 'Sign a test message'),
                ),
                TextButton.icon(
                  onPressed: () => connections.disconnect(network.family),
                  icon: const PhosphorIcon(PhosphorIconsRegular.plugs, size: 18),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ] else ...[
            Text(
              sdk
                  ? 'Let an SDK write the connection code: Reown AppKit opens one modal for hundreds of wallets '
                        'over WalletConnect, and near_wallet_connect does the same for NEAR wallets. The app still '
                        'decides what to sign.'
                  : 'Talk to wallets you already have, with no SDK: browser extensions through the standards they '
                        'announce themselves with, and wallet apps on phones.',
            ),
            const SizedBox(height: 12),
            if (wallets.isEmpty)
              Text(
                sdk ? _noSdkHint(network.family) : connections.finder.noneFoundHint(network.family),
                style: theme.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final wallet in wallets)
                    OutlinedButton.icon(
                      onPressed: connections.connecting != null ? null : () => connections.connect(wallet, network),
                      icon: connections.connecting == wallet
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : WalletIcon(wallet.icon, size: 18),
                      label: Text('Connect ${wallet.name}'),
                    ),
                ],
              ),
            if (!sdk && _onPhone && WalletBrowser.forFamily(network.family).isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                "Or open the web version in a wallet's browser, where it finds the wallet as it does on a desktop:",
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final browser in WalletBrowser.forFamily(network.family))
                    TextButton.icon(
                      onPressed: () => launchUrl(browser.linkTo(), mode: LaunchMode.externalApplication),
                      icon: const PhosphorIcon(PhosphorIconsRegular.globe, size: 18),
                      label: Text('Open in ${browser.name}'),
                    ),
                ],
              ),
            ],
            if (connections.connecting case final wallet? when mine) ...[
              const SizedBox(height: 8),
              Text('Approve the connection in ${wallet.name}.', style: theme.textTheme.bodySmall),
            ],
          ],
          if (connections.error case final error? when mine) ...[
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  /// Why there is no SDK option for [family] here.
  static String _noSdkHint(ChainFamily family) => switch (family) {
    ChainFamily.evm || ChainFamily.solana =>
      "Reown AppKit for Flutter runs on Android and iOS only. Here, use the wallets you have (option 2).",
    ChainFamily.sui => 'Sui wallets barely support WalletConnect yet, so this app leaves Sui to options 1 and 2.',
    ChainFamily.cosmos =>
      'No Flutter SDK connects Cosmos wallets on Osmosis testnet. Use the in-app wallet, or Keplr on the web.',
    ChainFamily.near => 'No NEAR wallet supports testnet here.',
  };

  Future<void> _signTest(InstalledSigner signer, Network network) async {
    final message = 'Hello from Flutter Counter!\nTime: ${DateTime.now().toUtc().toIso8601String()}';
    setState(() => signing = true);
    try {
      final signed = await signer.signMessage(message);
      final check = await verifier.verify(signed, evmChainId: network.isEvm ? network.chainId : null);
      widget.onSteps([
        HappeningStep(
          title: 'The message',
          detail: 'Plain text, chosen by the app. ${signer.name} showed it to you before signing.',
          code: message,
          status: StepStatus.done,
        ),
        ...explainSigning(signed),
        HappeningStep(
          title: check.valid ? 'Checked: the signature is valid' : 'The check failed',
          detail: check.valid ? check.how : check.reason,
          status: check.valid ? StepStatus.done : StepStatus.failed,
        ),
      ]);
    } catch (e) {
      widget.onSteps([HappeningStep(title: 'Not signed', detail: '$e', status: StepStatus.failed)]);
    } finally {
      if (mounted) setState(() => signing = false);
    }
  }
}

/// A wallet's logo, as the wallet announced it: usually a `data:` URI with
/// an SVG or PNG inside.
class WalletIcon extends StatelessWidget {
  const WalletIcon(this.icon, {super.key, this.size = 24});

  final String? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = PhosphorIcon(PhosphorIconsDuotone.wallet, size: size);
    final data = Uri.tryParse(icon?.trim() ?? '')?.data;
    if (data == null) return fallback;
    final Widget image;
    try {
      image = data.mimeType == 'image/svg+xml'
          ? SvgPicture.string(flattenNestedSvg(utf8.decode(data.contentAsBytes())), width: size, height: size)
          : Image.memory(data.contentAsBytes(), width: size, height: size, errorBuilder: (_, _, _) => fallback);
    } catch (_) {
      return fallback;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(size / 5), child: image);
  }
}

/// Turns `<svg>` elements nested inside an SVG into groups, which
/// flutter_svg can draw. (MetaMask's Wallet Standard icon nests one.) Each
/// becomes a `<g>` that moves and scales its viewBox into its x, y, width
/// and height.
String flattenNestedSvg(String svg) {
  final tags = RegExp(r'<svg\b([^>]*)>').allMatches(svg).toList();
  if (tags.length < 2) return svg;
  double attr(String attrs, String name, double fallback) =>
      double.tryParse(RegExp('\\b$name="([-\\d.]+)').firstMatch(attrs)?.group(1) ?? '') ?? fallback;

  final out = StringBuffer();
  var last = 0;
  for (final tag in tags.skip(1)) {
    final attrs = tag.group(1)!;
    final box = (RegExp(r'viewBox="([^"]+)"').firstMatch(attrs)?.group(1) ?? '')
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    final x = attr(attrs, 'x', 0), y = attr(attrs, 'y', 0);
    var transform = 'translate($x $y)';
    if (box.length == 4 && !box.contains(null)) {
      final sx = attr(attrs, 'width', box[2]!) / box[2]!;
      final sy = attr(attrs, 'height', box[3]!) / box[3]!;
      transform = 'translate(${x - box[0]! * sx} ${y - box[1]! * sy}) scale($sx $sy)';
    }
    out
      ..write(svg.substring(last, tag.start))
      ..write('<g transform="$transform">');
    last = tag.end;
  }
  out.write(svg.substring(last));
  // Every closing tag but the outer one closes a group now.
  final flat = out.toString();
  final end = flat.lastIndexOf('</svg>');
  return flat.substring(0, end).replaceAll('</svg>', '</g>') + flat.substring(end);
}
