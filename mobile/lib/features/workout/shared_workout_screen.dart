import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/units_provider.dart';
import 'workout_models.dart';
import 'workout_provider.dart';

/// Prompts for a share code, then pushes a read-only live view of that
/// workout — the "watch a friend train" entry point. Does nothing if the
/// user cancels or the code doesn't match a currently in-progress workout.
Future<void> showJoinSharedWorkoutDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Watch a shared workout'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(labelText: 'Share code'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim().toUpperCase()),
          child: const Text('Watch'),
        ),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;

  final workout = await ref.read(workoutRepositoryProvider).sharedWorkout(code);
  if (!context.mounted) return;
  if (workout == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("That code doesn't match an active workout")),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SharedWorkoutScreen(code: code, initial: workout)),
  );
}

/// Shows the current user's active workout's share code, so they can read
/// it out (or, in a fuller build, share it) to someone who wants to watch.
void showShareCodeDialog(BuildContext context, String? shareCode) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Share this workout'),
      content: shareCode == null
          ? const Text("This workout doesn't have a share code yet.")
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Give this code to a friend so they can watch your workout live:'),
                const SizedBox(height: 16),
                Text(
                  shareCode,
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
                ),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    ),
  );
}

/// Read-only live view of someone else's in-progress workout, joined via
/// share code. No ownership on the backend side (that's the point) — this
/// screen never calls any mutation, only the shared query + subscription.
class SharedWorkoutScreen extends ConsumerStatefulWidget {
  const SharedWorkoutScreen({super.key, required this.code, required this.initial});

  final String code;
  final Workout initial;

  @override
  ConsumerState<SharedWorkoutScreen> createState() => _SharedWorkoutScreenState();
}

class _SharedWorkoutScreenState extends ConsumerState<SharedWorkoutScreen> {
  late Workout _workout;
  StreamSubscription<LogSetResult>? _sub;

  @override
  void initState() {
    super.initState();
    _workout = widget.initial;
    _sub = ref.read(workoutRepositoryProvider).watchSharedWorkoutProgress(widget.code).listen((result) {
      if (_workout.sets.any((s) => s.id == result.set.id)) return;
      setState(() {
        _workout = Workout(
          id: _workout.id,
          startedAt: _workout.startedAt,
          status: _workout.status,
          notes: _workout.notes,
          templateId: _workout.templateId,
          shareCode: _workout.shareCode,
          sets: [..._workout.sets, result.set],
        );
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};
    final unit = ref.watch(weightUnitProvider);
    final groups = <String, List<WorkoutSet>>{};
    for (final set in _workout.sets) {
      groups.putIfAbsent(set.exerciseId, () => []).add(set);
    }

    return Scaffold(
      appBar: AppBar(title: Text('Live · ${widget.code}')),
      body: groups.isEmpty
          ? const Center(child: Text('No sets logged yet'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: groups.entries.map((entry) {
                final exercise = catalog[entry.key];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise?.name ?? 'Exercise', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        ...entry.value.map((set) {
                          final displayWeight = unit.fromKg(set.weightKg);
                          return Text(
                            '${set.reps} reps × ${displayWeight.toStringAsFixed(displayWeight.truncateToDouble() == displayWeight ? 0 : 1)} ${unit.label}',
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}
