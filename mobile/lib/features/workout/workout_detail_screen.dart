import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units/units_provider.dart';
import '../../core/units/weight_unit.dart';
import 'log_set_sheet.dart';
import 'workout_models.dart';
import 'workout_provider.dart';

/// Read-through view of a finished workout that also lets the user correct a
/// mis-logged set. Editing or deleting a set here recalculates personal
/// records on the server — the user is warned once per visit before the
/// first change. Pops with `true` if anything was changed, so the history
/// list can refresh.
class WorkoutDetailScreen extends ConsumerStatefulWidget {
  const WorkoutDetailScreen({super.key, required this.workout});

  final Workout workout;

  @override
  ConsumerState<WorkoutDetailScreen> createState() => _WorkoutDetailScreenState();
}

class _WorkoutDetailScreenState extends ConsumerState<WorkoutDetailScreen> {
  late List<WorkoutSet> _sets = [...widget.workout.sets];
  bool _changed = false;
  bool _warned = false;

  Future<bool> _confirmEditWarning() async {
    if (_warned) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit a finished workout?'),
        content: const Text(
          'Changing a set in a past session recalculates your personal records for that exercise. Continue?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) _warned = true;
    return ok ?? false;
  }

  Future<void> _editSet(WorkoutSet set) async {
    if (!await _confirmEditWarning()) return;
    final unit = ref.read(weightUnitProvider);
    final catalog = ref.read(exerciseCatalogProvider).asData?.value ?? const {};
    final exercise = catalog[set.exerciseId];
    if (exercise == null || !mounted) return;

    final input = await showLogSetSheet(context, exercise, editing: set, unit: unit);
    if (input == null) return;
    try {
      final updated = await ref.read(workoutRepositoryProvider).updateSet(
            setId: set.id,
            reps: input.reps,
            weightKg: input.weightKg,
            rpe: input.rpe,
            setType: input.setType,
          );
      setState(() {
        _sets = [for (final s in _sets) if (s.id == set.id) updated else s];
        _changed = true;
      });
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteSet(WorkoutSet set) async {
    if (!await _confirmEditWarning()) return;
    try {
      await ref.read(workoutRepositoryProvider).deleteSet(set.id);
      setState(() {
        _sets = [for (final s in _sets) if (s.id != set.id) s];
        _changed = true;
      });
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(weightUnitProvider);
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};

    final byExercise = <String, List<WorkoutSet>>{};
    for (final s in _sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Workout')),
        body: _sets.isEmpty
            ? const Center(child: Text('No sets in this workout.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final entry in byExercise.entries)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(catalog[entry.key]?.name ?? 'Exercise',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            for (final set in entry.value)
                              _SetRow(
                                set: set,
                                unit: unit,
                                onEdit: () => _editSet(set),
                                onDelete: () => _deleteSet(set),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.set, required this.unit, required this.onEdit, required this.onDelete});

  final WorkoutSet set;
  final WeightUnit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final w = unit.fromKg(set.weightKg);
    final weightStr = w.toStringAsFixed(w.truncateToDouble() == w ? 0 : 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('${set.setNumber}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text('${set.reps} × $weightStr ${unit.label}', style: Theme.of(context).textTheme.bodyMedium),
          if (set.setType != SetType.normal) ...[
            const SizedBox(width: 8),
            Text(set.setType.badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
          if (set.rpe != null) ...[
            const SizedBox(width: 8),
            Text('RPE ${set.rpe}', style: Theme.of(context).textTheme.bodySmall),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
