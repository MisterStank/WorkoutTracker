import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/units_provider.dart';
import '../sharing/pr_share_card.dart';
import '../sharing/share_preview_sheet.dart';
import '../sharing/workout_summary_share_card.dart';
import 'workout_models.dart';
import 'workout_provider.dart';

/// Shown right after finishing a workout with at least one set — the result
/// screen the app was missing: duration/volume/sets, what was trained, any
/// PRs earned along the way, and sharing, all in one place instead of a
/// SnackBar that vanished in a few seconds. Terminal screen: the only way
/// out is "Done", which returns to the app root.
class WorkoutCompletionScreen extends ConsumerWidget {
  const WorkoutCompletionScreen({super.key, required this.workout, required this.newRecords});

  final Workout workout;
  final List<PersonalRecord> newRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};
    final unit = ref.watch(weightUnitProvider);

    final exerciseNames = {
      for (final set in workout.sets) catalog[set.exerciseId]?.name ?? 'Exercise',
    }.toList();
    final workingSets = workout.sets.where((s) => s.setType != SetType.warmup).toList();
    final totalVolumeKg = workingSets.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps);
    final displayVolume = unit.fromKg(totalVolumeKg);
    final duration = (workout.endedAt ?? DateTime.now()).difference(workout.startedAt);
    final durationLabel = duration.inHours > 0 ? '${duration.inHours}h ${duration.inMinutes % 60}m' : '${duration.inMinutes}m';

    final recordsByExercise = <String, List<PersonalRecord>>{};
    for (final r in newRecords) {
      recordsByExercise.putIfAbsent(r.exerciseId, () => []).add(r);
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
            children: [
              Icon(Icons.check_circle, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Workout complete!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatColumn(label: 'Sets', value: '${workingSets.length}'),
                  _StatColumn(label: 'Volume', value: '${displayVolume.toStringAsFixed(0)} ${unit.label}'),
                  _StatColumn(label: 'Time', value: durationLabel),
                ],
              ),
              if (exerciseNames.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  exerciseNames.join(' · '),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              if (recordsByExercise.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text('New personal records', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...recordsByExercise.entries.map((entry) {
                  final exerciseName = catalog[entry.key]?.name ?? 'Exercise';
                  final labels = entry.value.map((r) => recordTypeLabels[r.recordType] ?? r.recordType).join(' & ');
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.emoji_events, color: Theme.of(context).colorScheme.primary),
                      title: Text(exerciseName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(labels),
                      trailing: IconButton(
                        icon: const Icon(Icons.ios_share, size: 18),
                        tooltip: 'Share',
                        onPressed: () => showSharePreview(
                          context,
                          card: PrShareCard(exerciseName: exerciseName, records: entry.value, unit: unit),
                          filename: 'pr_$exerciseName',
                        ),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => showSharePreview(
                  context,
                  card: WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: unit),
                  filename: 'workout_${workout.id}',
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share workout summary'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
