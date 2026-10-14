import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../chains/networks.dart';
import '../layout.dart';
import '../theme.dart';

/// An address or contract ID that never wraps in the middle of the text.
///
/// On a wide window the whole address is shown and can be selected. On
/// narrower ones it is shortened in the middle ("0xFFFAa29e...01aCce47"),
/// which is how wallets show addresses, because the ends are what people
/// compare. Copy always copies the full address.
class AddressView extends StatelessWidget {
  const AddressView({super.key, required this.address, this.network, this.size = 13});

  final String address;

  /// When given, an "open in the explorer" button links to the address there.
  final Network? network;

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = monoStyle(context, size: size);
    final full = WindowSize.of(context).isExpanded;
    return Row(
      children: [
        Expanded(
          child: full
              ? SelectableText(address, style: style)
              // Shrinks a little, rather than wrapping, when even the short form does not fit.
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(shortAddress(address, head: 10, tail: 8), style: style),
                ),
        ),
        IconButton(
          tooltip: 'Copy the address',
          icon: PhosphorIcon(PhosphorIconsRegular.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
        ),
        if (network case final network?)
          IconButton(
            tooltip: 'View on the explorer',
            icon: PhosphorIcon(PhosphorIconsRegular.arrowSquareOut, size: 18),
            onPressed: () => launchUrl(Uri.parse(network.addressUrl(address))),
          ),
      ],
    );
  }
}
