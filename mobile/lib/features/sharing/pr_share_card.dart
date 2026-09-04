import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/units/weight_unit.dart';
import '../workout/workout_models.dart';

/// A shareable "I just hit a PR" card — fixed size, fixed dark-on-brick-red
/// palette regardless of the app's current theme, so the exported image
/// looks the same for everyone regardless of who's viewing it.
class PrShareCard extends StatelessWidget {
  const PrShareCard({super.key, required this.exerciseName, required this.records, required this.unit});

  final String exerciseName;
  final List<PersonalRecord> records;
  final WeightUnit unit;

  static const _background = Color(0xFF3D1410);
  static const _accent = Color(0xFFE8663F);
  static const _text = Color(0xFFFFF3ED);

  @override
  Widget build(BuildContext context) {
    final headline = records.first;
    final labels = records.map((r) => recordTypeLabels[r.recordType] ?? r.recordType).join(' & ');

    // "most reps" is a plain count, not a weight — don't unit-convert or tack a
    // kg/lb label onto it. Everything else (heaviest weight, best volume,
    // estimated 1RM) is a weight in kg.
    final String headlineText;
    if (headline.recordType == 'max_reps') {
      headlineText = '${headline.value.toStringAsFixed(0)} reps';
    } else {
      final displayValue = unit.fromKg(headline.value);
      final n = displayValue.toStringAsFixed(displayValue.truncateToDouble() == displayValue ? 0 : 1);
      headlineText = '$n ${unit.label}';
    }

    return Container(
      width: 340,
      height: 340,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_background, Color(0xFF17191A)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.emoji_events, color: _accent, size: 40),
          const SizedBox(height: 10),
          const Text('NEW PERSONAL RECORD',
              style: TextStyle(fontFamily: AppTypography.display, color: _accent, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          // A long exercise name or headline must shrink to one line rather than
          // wrap — wrapping pushes the "GYMON" footer out of the fixed-size card
          // and clips it in the exported image.
          _OneLine(
            exerciseName,
            style: const TextStyle(fontFamily: AppTypography.display, color: _text, fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          _OneLine(
            headlineText,
            style: const TextStyle(fontFamily: AppTypography.mono, color: _text, fontSize: 46, fontWeight: FontWeight.w600, letterSpacing: -1),
          ),
          Text(labels, style: TextStyle(fontFamily: AppTypography.body, color: _text.withValues(alpha: 0.8), fontSize: 14)),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _accent, size: 16),
              const SizedBox(width: 6),
              Text('GYMON',
                  style: TextStyle(fontFamily: AppTypography.display, color: _text.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Left-aligned text that scales down to a single line instead of wrapping.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      ),
    );
  }
}
