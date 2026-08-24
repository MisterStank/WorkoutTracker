import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/app_database.dart' show offlineQueueSupported;
import '../../core/offline/sync_service.dart';
import '../../core/units/units_provider.dart';
import '../../core/units/weight_unit.dart';
import '../analytics/analytics_screen.dart';
import '../auth/auth_provider.dart';
import '../templates/template_models.dart';
import '../templates/template_provider.dart';
import '../templates/templates_screen.dart';
import 'exercise_picker_screen.dart';
import 'log_set_sheet.dart';
import 'rest_timer_provider.dart';
import 'workout_history_screen.dart';
import 'workout_models.dart';
import 'workout_provider.dart';
import 'workout_state.dart';

class WorkoutHomeScreen extends ConsumerWidget {
  const WorkoutHomeScreen({super.key});

  Future<void> _logNewSet(BuildContext context, WidgetRef ref) async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null || !context.mounted) return;
    await _logSetForExercise(context, ref, exercise);
  }

  static Future<void> _logSetForExercise(BuildContext context, WidgetRef ref, Exercise exercise) async {
    final unit = ref.read(weightUnitProvider);
    final lastSet = await ref.read(workoutRepositoryProvider).lastSetForExercise(exercise.id);
    if (!context.mounted) return;

    final input = await showLogSetSheet(context, exercise, lastSet: lastSet, unit: unit);
    if (input == null) return;

    await ref.read(activeWorkoutProvider.notifier).logSet(
          exerciseId: exercise.id,
          reps: input.reps,
          weightKg: input.weightKg,
          rpe: input.rpe,
          setType: input.setType,
        );
    ref.read(restTimerProvider.notifier).start();
  }

  Future<void> _startWorkout(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Blank workout'),
              onTap: () => Navigator.of(context).pop('blank'),
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('From a template'),
              onTap: () => Navigator.of(context).pop('template'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == 'blank') {
      await ref.read(activeWorkoutProvider.notifier).start();
    } else if (choice == 'template') {
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen()));
      }
    }
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Finish workout'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Finish'),
            ),
          ],
        );
      },
    );
    if (notes == null) return;
    await ref.read(activeWorkoutProvider.notifier).finish(notes: notes.isEmpty ? null : notes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeWorkoutProvider);
    final unit = ref.watch(weightUnitProvider);
    // Keeps SyncService alive for as long as the home screen is mounted, so
    // queued offline sets get pushed as soon as connectivity returns even
    // if the user never re-opens the active-workout screen themselves.
    if (offlineQueueSupported) ref.watch(syncServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkoutTracker'),
        actions: [
          TextButton(
            onPressed: () => ref.read(weightUnitProvider.notifier).toggle(),
            child: Text(unit.label.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Progress',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Templates',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: state is ActiveWorkoutInProgress
          ? FloatingActionButton.extended(
              onPressed: () => _logNewSet(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Log set'),
            )
          : null,
      body: switch (state) {
        ActiveWorkoutLoading() => const Center(child: CircularProgressIndicator()),
        ActiveWorkoutError(:final message) => _ErrorView(message: message),
        ActiveWorkoutNone() => _StartWorkoutView(onStart: () => _startWorkout(context, ref)),
        ActiveWorkoutInProgress(:final workout, :final lastNewRecords) => _ActiveWorkoutView(
            workout: workout,
            lastNewRecords: lastNewRecords,
            onFinish: () => _finish(context, ref),
          ),
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StartWorkoutView extends StatelessWidget {
  const _StartWorkoutView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No workout in progress', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Start a session to begin logging sets.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start workout'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveWorkoutView extends ConsumerWidget {
  const _ActiveWorkoutView({required this.workout, required this.lastNewRecords, required this.onFinish});

  final Workout workout;
  final List<PersonalRecord> lastNewRecords;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};
    final groups = <String, List<WorkoutSet>>{};
    for (final set in workout.sets) {
      groups.putIfAbsent(set.exerciseId, () => []).add(set);
    }

    WorkoutTemplate? template;
    if (workout.templateId != null) {
      template = ref.watch(templateCatalogProvider).asData?.value[workout.templateId];
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  _ElapsedTimeText(startedAt: workout.startedAt),
                ],
              ),
              Text('${workout.sets.length} set${workout.sets.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (template != null)
          _PlannedExercisesRow(
            template: template,
            catalog: catalog,
            loggedCounts: {for (final e in groups.entries) e.key: e.value.where((s) => s.setType != SetType.warmup).length},
            onTapExercise: (exercise) => WorkoutHomeScreen._logSetForExercise(context, ref, exercise),
          ),
        if (lastNewRecords.isNotEmpty) _NewRecordBanner(records: lastNewRecords),
        const _RestTimerBanner(),
        Expanded(
          child: groups.isEmpty
              ? const _EmptyWorkoutHint()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: groups.entries.map((entry) {
                    final exercise = catalog[entry.key];
                    return _ExerciseGroupCard(
                      exerciseName: exercise?.name ?? 'Exercise',
                      sets: entry.value,
                      unit: ref.watch(weightUnitProvider),
                      onRepeatLast: () {
                        final last = entry.value.last;
                        ref.read(activeWorkoutProvider.notifier).logSet(
                              exerciseId: last.exerciseId,
                              reps: last.reps,
                              weightKg: last.weightKg,
                              rpe: last.rpe,
                              setType: last.setType,
                              supersetId: last.supersetId,
                            );
                        ref.read(restTimerProvider.notifier).start();
                      },
                    );
                  }).toList(),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: OutlinedButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Finish workout'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Quick-tap chips for a workout's planned exercises (from its template),
/// so the user can jump straight to logging a set for the next planned
/// exercise without going through the search picker.
class _PlannedExercisesRow extends StatelessWidget {
  const _PlannedExercisesRow({
    required this.template,
    required this.catalog,
    required this.loggedCounts,
    required this.onTapExercise,
  });

  final WorkoutTemplate template;
  final Map<String, Exercise> catalog;
  final Map<String, int> loggedCounts;
  final void Function(Exercise exercise) onTapExercise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: template.exercises.length,
          separatorBuilder: (context, index) {
            // A link icon between two chips sharing a superset group,
            // instead of the default gap, visually brackets them together.
            final a = template.exercises[index];
            final b = template.exercises[index + 1];
            final linked = a.supersetGroup != null && a.supersetGroup == b.supersetGroup;
            if (!linked) return const SizedBox(width: 8);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.link, size: 14, color: Theme.of(context).colorScheme.primary),
            );
          },
          itemBuilder: (context, index) {
            final planned = template.exercises[index];
            final exercise = catalog[planned.exerciseId];
            final done = loggedCounts[planned.exerciseId] ?? 0;
            final complete = done >= planned.targetSets;
            return ActionChip(
              avatar: complete
                  ? const Icon(Icons.check_circle, size: 16, color: Colors.green)
                  : const Icon(Icons.fitness_center, size: 16),
              label: Text('${exercise?.name ?? 'Exercise'} $done/${planned.targetSets}'),
              backgroundColor: planned.supersetGroup != null ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
              onPressed: exercise == null ? null : () => onTapExercise(exercise),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyWorkoutHint extends StatelessWidget {
  const _EmptyWorkoutHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_add, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('No sets logged yet'),
          const SizedBox(height: 4),
          Text('Tap "Log set" to add your first one.', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _NewRecordBanner extends StatelessWidget {
  const _NewRecordBanner({required this.records});

  final List<PersonalRecord> records;

  static const _labels = {
    'max_weight': 'heaviest weight',
    'max_volume': 'best volume',
    'estimated_1rm': 'estimated 1RM',
  };

  @override
  Widget build(BuildContext context) {
    final labels = records.map((r) => _labels[r.recordType] ?? r.recordType).join(' & ');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.amber.shade400, Colors.orange.shade400]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'New personal record — $labels!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestTimerBanner extends ConsumerWidget {
  const _RestTimerBanner();

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    if (!timer.running) return const SizedBox.shrink();

    final progress = timer.total.inSeconds == 0 ? 0.0 : timer.remaining.inSeconds / timer.total.inSeconds;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: progress, strokeWidth: 3),
              const Icon(Icons.timer, size: 14),
            ]),
          ),
          const SizedBox(width: 10),
          Text('Rest: ${_format(timer.remaining)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: '+15s',
            visualDensity: VisualDensity.compact,
            onPressed: () => ref.read(restTimerProvider.notifier).addSeconds(15),
          ),
          TextButton(
            onPressed: () => ref.read(restTimerProvider.notifier).skip(),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}

Color _setTypeColor(SetType type, BuildContext context) => switch (type) {
      SetType.warmup => Colors.blueGrey.shade100,
      SetType.dropset => Colors.orange.shade100,
      SetType.failure => Colors.red.shade100,
      SetType.normal => Colors.transparent,
    };

class _ExerciseGroupCard extends StatelessWidget {
  const _ExerciseGroupCard({required this.exerciseName, required this.sets, required this.unit, required this.onRepeatLast});

  final String exerciseName;
  final List<WorkoutSet> sets;
  final WeightUnit unit;
  final VoidCallback onRepeatLast;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(exerciseName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: onRepeatLast,
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Repeat last'),
                ),
              ],
            ),
            ...sets.map((set) {
              final displayWeight = unit.fromKg(set.weightKg);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${set.setNumber}', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                    Text('${set.reps} reps', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 10),
                    Text('×', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(width: 10),
                    Text(
                      '${displayWeight.toStringAsFixed(displayWeight.truncateToDouble() == displayWeight ? 0 : 1)} ${unit.label}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (set.setType != SetType.normal) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: set.setType.label,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _setTypeColor(set.setType, context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(set.setType.badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    if (set.supersetId != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.link, size: 13, color: Theme.of(context).colorScheme.primary),
                    ],
                    if (set.rpe != null) ...[
                      const SizedBox(width: 10),
                      Chip(
                        label: Text('RPE ${set.rpe}', style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                    if (set.isPending) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Saved offline — will sync when back online',
                        child: Icon(Icons.cloud_off, size: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ElapsedTimeText extends StatefulWidget {
  const _ElapsedTimeText({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_ElapsedTimeText> createState() => _ElapsedTimeTextState();
}

class _ElapsedTimeTextState extends State<_ElapsedTimeText> {
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
    return Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600));
  }
}
