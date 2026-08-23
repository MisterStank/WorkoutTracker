import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'exercise_picker_screen.dart';
import 'log_set_sheet.dart';
import 'workout_history_screen.dart';
import 'workout_provider.dart';
import 'workout_state.dart';

class WorkoutHomeScreen extends ConsumerWidget {
  const WorkoutHomeScreen({super.key});

  Future<void> _logSet(BuildContext context, WidgetRef ref) async {
    final exercise = await Navigator.of(context).push(
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
          content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Notes (optional)')),
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WorkoutHistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: switch (state) {
        ActiveWorkoutLoading() => const Center(child: CircularProgressIndicator()),
        ActiveWorkoutError(:final message) => Center(child: Text('Error: $message')),
        ActiveWorkoutNone() => Center(
            child: FilledButton(
              onPressed: () => ref.read(activeWorkoutProvider.notifier).start(),
              child: const Text('Start workout'),
            ),
          ),
        ActiveWorkoutInProgress(:final workout, :final lastNewRecords) => Column(
            children: [
              if (lastNewRecords.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Colors.amber.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'New PR! ${lastNewRecords.map((r) => r.recordType).join(', ')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              Expanded(
                child: workout.sets.isEmpty
                    ? const Center(child: Text('No sets logged yet'))
                    : ListView.builder(
                        itemCount: workout.sets.length,
                        itemBuilder: (context, index) {
                          final set = workout.sets[index];
                          return ListTile(
                            leading: CircleAvatar(child: Text('${set.setNumber}')),
                            title: Text('${set.reps} reps @ ${set.weightKg} kg'),
                            subtitle: set.rpe == null ? null : Text('RPE ${set.rpe}'),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(onPressed: () => _logSet(context, ref), child: const Text('Log set')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _finish(context, ref),
                        child: const Text('Finish workout'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      },
    );
  }
}
