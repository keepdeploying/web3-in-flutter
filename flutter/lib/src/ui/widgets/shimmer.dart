import 'package:flutter/material.dart';

/// A placeholder box with a light sweeping across it, shown while data loads.
///
/// Showing the rough shape of what is coming feels faster than a spinner,
/// and the layout doesn't jump when the real data arrives.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = (dark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    final light = (dark ? Colors.white : Colors.white).withValues(alpha: dark ? 0.22 : 0.8);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Slide a bright band from left (-1) to right (+2) across the box.
        final t = controller.value * 3 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 1, 0),
              end: Alignment(t + 1, 0),
              colors: [base, light, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}
