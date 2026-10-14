import 'package:flutter/material.dart';

/// The app's icon with rounded corners, for the top bar and the rail.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 2 / 7),
      child: Image.asset(
        'assets/icon/icon.png',
        width: size,
        height: size,
        // The file is 1024 px wide: decode it small, since it is only ever shown small.
        cacheWidth: 128,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}
