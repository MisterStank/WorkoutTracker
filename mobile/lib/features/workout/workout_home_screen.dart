import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'exercise_picker_screen.dart';
import 'log_set_sheet.dart';
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

    final input = await showLogSetSheet(context, exercise);
    if (input == null) return;

    await ref
        .read(activeWorkoutProvider.notifier)
        .logSet(exerciseId: exercise.id, reps: input.reps, weightKg: input.weightKg, rpe: input.rpe);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkoutTracker'),
        actions: [
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
        ActiveWorkoutNone() => _StartWorkoutView(onStart: () => ref.read(activeWorkoutProvider.notifier).start()),
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
        if (lastNewRecords.isNotEmpty) _NewRecordBanner(records: lastNewRecords),
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
                      onRepeatLast: () {
                        final last = entry.value.last;
                        ref.read(activeWorkoutProvider.notifier).logSet(
                              exerciseId: last.exerciseId,
                              reps: last.reps,
                              weightKg: last.weightKg,
                              rpe: last.rpe,
                            );
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

  static const _labels = {'max_weight': 'heaviest weight', 'max_volume': 'best volume'};

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

class _ExerciseGroupCard extends StatelessWidget {
  const _ExerciseGroupCard({required this.exerciseName, required this.sets, required this.onRepeatLast});

  final String exerciseName;
  final List<WorkoutSet> sets;
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
            ...sets.map((set) => Padding(
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
                      Text('${set.weightKg.toStringAsFixed(set.weightKg.truncateToDouble() == set.weightKg ? 0 : 1)} kg',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                      if (set.rpe != null) ...[
                        const SizedBox(width: 10),
                        Chip(
                          label: Text('RPE ${set.rpe}', style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ],
                  ),
                )),
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
