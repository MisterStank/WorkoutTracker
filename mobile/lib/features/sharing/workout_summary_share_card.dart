import 'package:flutter/material.dart';

import '../../core/units/weight_unit.dart';
import '../workout/workout_models.dart';

/// A shareable workout-summary card — date, duration, sets, volume, and
/// the exercises trained. Same fixed dark-on-brick-red palette as
/// [PrShareCard], deliberately independent of the app's light/dark setting.
class WorkoutSummaryShareCard extends StatelessWidget {
  const WorkoutSummaryShareCard({super.key, required this.workout, required this.exerciseNames, required this.unit});

  final Workout workout;
  final List<String> exerciseNames;
  final WeightUnit unit;

  static const _background = Color(0xFF3D1410);
  static const _accent = Color(0xFFE8663F);
  static const _text = Color(0xFFFFF3ED);

  @override
  Widget build(BuildContext context) {
    final workingSets = workout.sets.where((s) => s.setType != SetType.warmup).toList();
    final totalVolumeKg = workingSets.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps);
    final displayVolume = unit.fromKg(totalVolumeKg);
    final duration = (workout.endedAt ?? DateTime.now()).difference(workout.startedAt);
    final durationLabel = duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes % 60}m' : '${duration.inMinutes}m';

    return Container(
      width: 360,
      height: 400,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_background, Color(0xFF17191A)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WORKOUT COMPLETE', style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'Sets', value: '${workingSets.length}'),
              _Stat(label: 'Volume', value: '${displayVolume.toStringAsFixed(0)} ${unit.label}'),
              _Stat(label: 'Time', value: durationLabel),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Text(
              exerciseNames.join(' · '),
              style: TextStyle(color: _text.withValues(alpha: 0.85), fontSize: 15, height: 1.4),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: WorkoutSummaryShareCard._text, fontSize: 22, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: WorkoutSummaryShareCard._text.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }
}
