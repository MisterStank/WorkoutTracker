import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';

/// A ticking "N min" / "Just started" label for an in-progress workout —
/// shared between the active-workout header and AppShell's persistent
/// resume bar, so both read the same elapsed time.
class ElapsedTimeText extends StatefulWidget {
  const ElapsedTimeText({super.key, required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<ElapsedTimeText> createState() => _ElapsedTimeTextState();
}

class _ElapsedTimeTextState extends State<ElapsedTimeText> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final minutes = elapsed.inMinutes;
    final text = minutes < 1 ? 'Just started' : '$minutes min';
    return Text(text, style: widget.style ?? Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: AppTypography.mono, fontWeight: FontWeight.w600));
  }
}
