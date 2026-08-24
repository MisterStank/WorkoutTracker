import 'package:flutter/material.dart';

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
    final displayValue = unit.fromKg(headline.value);
    final labels = records.map((r) => recordTypeLabels[r.recordType] ?? r.recordType).join(' & ');

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
          const SizedBox(height: 12),
          const Text('NEW PERSONAL RECORD', style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text(exerciseName, style: const TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '${displayValue.toStringAsFixed(displayValue.truncateToDouble() == displayValue ? 0 : 1)} ${unit.label}',
            style: const TextStyle(color: _text, fontSize: 48, fontWeight: FontWeight.w800),
          ),
          Text(labels, style: TextStyle(color: _text.withValues(alpha: 0.8), fontSize: 14)),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _accent, size: 16),
              const SizedBox(width: 6),
              Text('WorkoutTracker', style: TextStyle(color: _text.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
