import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../chains/networks.dart';

/// A network's logo in a small white disc.
///
/// The disc keeps dark logos (Arbitrum, Optimism) readable on dark glass, and
/// the thin border keeps white ones from vanishing on light glass.
class NetworkLogo extends StatelessWidget {
  const NetworkLogo(this.network, {super.key, this.size = 24});

  final Network network;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // The SVGs already have a margin, so a little padding is enough.
      padding: EdgeInsets.all(size / 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
      ),
      child: SvgPicture.asset(network.logo, semanticsLabel: network.name),
    );
  }
}
