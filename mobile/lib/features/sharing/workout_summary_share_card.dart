import 'package:flutter/material.dart';

import '../../core/theme/app_typography.dart';
import '../../core/units/weight_unit.dart';
import '../workout/workout_models.dart';

/// One exercise's block on the summary card: every working set (not just
/// the best one — matches how Hevy's share card reads, more complete than
/// a single top-set summary), plus whether any of them was a PR this
/// session.
class _ExerciseSummary {
  _ExerciseSummary(this.name);

  final String name;
  final List<WorkoutSet> sets = [];
  bool isPr = false;
}

/// A shareable workout-summary card — who did it, what it was called, when,
/// duration/sets/volume, a full per-exercise set-by-set breakdown, and a PR
/// callout inline on any exercise that earned one — closing the gap against
/// Hevy/Strong-style workout cards, which always sign, title, and date the
/// card and fold the PR story into the same image rather than a separate
/// one. Same fixed dark-on-brick-red palette as [PrShareCard], deliberately
/// independent of the app's light/dark setting. Sized to its content
/// (no fixed height) since a full set-by-set breakdown varies a lot by
/// workout length.
class WorkoutSummaryShareCard extends StatelessWidget {
  const WorkoutSummaryShareCard({
    super.key,
    required this.workout,
    required this.catalog,
    required this.unit,
    this.displayName,
    this.title,
    this.newRecords = const [],
  });

  final Workout workout;
  final Map<String, Exercise> catalog;
  final WeightUnit unit;
  // The user's name, shown as "Logged by <name>" — null (or empty) omits
  // that line rather than showing a blank/anonymous credit.
  final String? displayName;
  // The workout/day name (e.g. a program day's label, or a template's
  // name) to headline the card with, in place of a generic label. Null
  // falls back to a weekday-based title ("Tuesday Workout").
  final String? title;
  // PRs earned during this workout, if known — flags a trophy badge on
  // every exercise that hit one. History doesn't have this after the fact
  // (only known at finish-time), so it's optional and defaults to none.
  final List<PersonalRecord> newRecords;

  static const _background = Color(0xFF3D1410);
  static const _accent = Color(0xFFE8663F);
  static const _text = Color(0xFFFFF3ED);
  static const _maxExercises = 10;

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    final workingSets = workout.sets.where((s) => s.setType != SetType.warmup).toList();
    final totalVolumeKg = workingSets.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps);
    final displayVolume = unit.fromKg(totalVolumeKg);
    final duration = (workout.endedAt ?? DateTime.now()).difference(workout.startedAt);
    final durationLabel = duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes % 60}m' : '${duration.inMinutes}m';

    final prExerciseIds = newRecords.map((r) => r.exerciseId).toSet();
    final byExercise = <String, _ExerciseSummary>{};
    for (final set in workout.sets) {
      if (set.setType == SetType.warmup) continue;
      final name = catalog[set.exerciseId]?.name ?? 'Exercise';
      final summary = byExercise.putIfAbsent(set.exerciseId, () => _ExerciseSummary(name));
      summary.sets.add(set);
      if (prExerciseIds.contains(set.exerciseId)) summary.isPr = true;
    }
    final exercises = byExercise.values.toList();
    final shown = exercises.take(_maxExercises).toList();
    final overflow = exercises.length - shown.length;

    final local = workout.startedAt.toLocal();
    final dateLabel = '${_weekdays[local.weekday - 1].substring(0, 3)} ${local.month}/${local.day}';
    final headline = title?.trim().isNotEmpty == true ? title!.trim() : '${_weekdays[local.weekday - 1]} Workout';

    return Container(
      width: 360,
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_background, Color(0xFF17191A)]),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('WORKOUT COMPLETE',
              style: TextStyle(fontFamily: AppTypography.display, color: _accent, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Text(headline,
              style: const TextStyle(fontFamily: AppTypography.display, color: _text, fontSize: 26, fontWeight: FontWeight.w800),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            [if (displayName != null && displayName!.trim().isNotEmpty) displayName!.trim(), dateLabel].join(' · '),
            style: TextStyle(color: _text.withValues(alpha: 0.6), fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat(label: 'Sets', value: '${workingSets.length}'),
              _Stat(label: 'Volume', value: '${displayVolume.toStringAsFixed(0)} ${unit.label}'),
              _Stat(label: 'Time', value: durationLabel),
            ],
          ),
          const SizedBox(height: 18),
          for (final e in shown) _ExerciseBlock(summary: e, unit: unit),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text('+$overflow more exercise${overflow == 1 ? '' : 's'}', style: TextStyle(color: _text.withValues(alpha: 0.6), fontSize: 13)),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.fitness_center, color: _accent, size: 16),
              const SizedBox(width: 6),
              Text('WORKOUTTRACKER',
                  style: TextStyle(fontFamily: AppTypography.display, color: _text.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.summary, required this.unit});

  final _ExerciseSummary summary;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.name,
                  style: const TextStyle(color: WorkoutSummaryShareCard._text, fontSize: 15, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (summary.isPr) ...[
                const SizedBox(width: 6),
                const Icon(Icons.emoji_events, color: WorkoutSummaryShareCard._accent, size: 15),
                const SizedBox(width: 2),
                const Text('PR',
                    style: TextStyle(fontFamily: AppTypography.display, color: WorkoutSummaryShareCard._accent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ],
            ],
          ),
          const SizedBox(height: 3),
          for (var i = 0; i < summary.sets.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: Text('${i + 1}',
                        style: TextStyle(fontFamily: AppTypography.mono, color: WorkoutSummaryShareCard._text.withValues(alpha: 0.45), fontSize: 12)),
                  ),
                  Text(
                    '${summary.sets[i].reps} × ${unit.fromKg(summary.sets[i].weightKg).toStringAsFixed(0)} ${unit.label}',
                    style: TextStyle(fontFamily: AppTypography.mono, color: WorkoutSummaryShareCard._text.withValues(alpha: 0.85), fontSize: 13),
                  ),
                ],
              ),
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
        Text(value, style: const TextStyle(fontFamily: AppTypography.mono, color: WorkoutSummaryShareCard._text, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
        Text(label, style: TextStyle(fontFamily: AppTypography.body, color: WorkoutSummaryShareCard._text.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }
}
