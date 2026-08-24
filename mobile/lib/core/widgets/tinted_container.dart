import 'package:flutter/material.dart';

/// A softly-tinted rounded box — the "this is grouped/selected/highlighted"
/// treatment used for superset chips, planned-exercise chips, and inline
/// guidance boxes. Previously each screen built this by hand with its own
/// `.withValues(alpha: 0.4)` call; centralizing it keeps the tint consistent
/// wherever it shows up.
class TintedContainer extends StatelessWidget {
  const TintedContainer({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.radius = 10,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.primaryContainer;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
