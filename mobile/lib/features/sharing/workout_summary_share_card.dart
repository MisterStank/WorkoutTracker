import 'package:flutter/material.dart';

import '../../core/units/weight_unit.dart';
import '../workout/workout_models.dart';

/// One exercise's line on the summary card: name, working-set count, and
/// the heaviest working set (by weight, ties broken by reps) — enough for
/// someone glancing at the shared image to see what was actually trained,
/// not just a list of names.
class _ExerciseSummary {
  _ExerciseSummary(this.name);

  final String name;
  int setCount = 0;
  WorkoutSet? best;

  void addSet(WorkoutSet set) {
    setCount++;
    if (best == null || set.weightKg > best!.weightKg || (set.weightKg == best!.weightKg && set.reps > best!.reps)) {
      best = set;
    }
  }
}

/// A shareable workout-summary card — date, duration, sets, volume, and a
/// per-exercise breakdown (sets done + best set) rather than just a list of
/// exercise names. Same fixed dark-on-brick-red palette as [PrShareCard],
/// deliberately independent of the app's light/dark setting.
class WorkoutSummaryShareCard extends StatelessWidget {
  const WorkoutSummaryShareCard({super.key, required this.workout, required this.catalog, required this.unit});

  final Workout workout;
  final Map<String, Exercise> catalog;
  final WeightUnit unit;

  static const _background = Color(0xFF3D1410);
  static const _accent = Color(0xFFE8663F);
  static const _text = Color(0xFFFFF3ED);
  static const _maxRows = 5;

  @override
  Widget build(BuildContext context) {
    final workingSets = workout.sets.where((s) => s.setType != SetType.warmup).toList();
    final totalVolumeKg = workingSets.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps);
    final displayVolume = unit.fromKg(totalVolumeKg);
    final duration = (workout.endedAt ?? DateTime.now()).difference(workout.startedAt);
    final durationLabel = duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes % 60}m' : '${duration.inMinutes}m';

    final byExercise = <String, _ExerciseSummary>{};
    for (final set in workout.sets) {
      final name = catalog[set.exerciseId]?.name ?? 'Exercise';
      final summary = byExercise.putIfAbsent(set.exerciseId, () => _ExerciseSummary(name));
      if (set.setType != SetType.warmup) summary.addSet(set);
    }
    final exercises = byExercise.values.where((e) => e.setCount > 0).toList();
    final shown = exercises.take(_maxRows).toList();
    final overflow = exercises.length - shown.length;

    return Container(
      width: 360,
      height: 460,
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
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final e in shown) _ExerciseRow(summary: e, unit: unit),
                if (overflow > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+$overflow more', style: TextStyle(color: _text.withValues(alpha: 0.6), fontSize: 13)),
                  ),
              ],
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

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.summary, required this.unit});

  final _ExerciseSummary summary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final best = summary.best;
    final bestLabel = best == null ? '' : '${best.reps} × ${unit.fromKg(best.weightKg).toStringAsFixed(0)} ${unit.label}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary.name,
              style: const TextStyle(color: WorkoutSummaryShareCard._text, fontSize: 15, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${summary.setCount} set${summary.setCount == 1 ? '' : 's'}',
            style: TextStyle(color: WorkoutSummaryShareCard._text.withValues(alpha: 0.6), fontSize: 13),
          ),
          if (bestLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(bestLabel, style: const TextStyle(color: WorkoutSummaryShareCard._accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
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
