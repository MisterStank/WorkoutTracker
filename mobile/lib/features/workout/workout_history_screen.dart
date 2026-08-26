import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/units/units_provider.dart';
import '../sharing/share_preview_sheet.dart';
import '../sharing/workout_summary_share_card.dart';
import 'workout_models.dart';
import 'workout_provider.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${_months[local.month - 1]} ${local.day} · $hour:$minute $period';
}

class WorkoutHistoryScreen extends ConsumerStatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  ConsumerState<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends ConsumerState<WorkoutHistoryScreen> {
  final List<Workout> _workouts = [];
  String? _cursor;
  bool _hasNextPage = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text('This removes the whole session and its sets. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteWorkout(Workout workout) async {
    setState(() => _workouts.removeWhere((w) => w.id == workout.id));
    try {
      await ref.read(workoutRepositoryProvider).deleteWorkout(workout.id);
    } catch (e) {
      if (mounted) {
        setState(() => _workouts.add(workout));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNextPage) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(workoutRepositoryProvider).workoutHistory(first: 20, after: _cursor);
      setState(() {
        _workouts.addAll(page.workouts);
        _cursor = page.endCursor;
        _hasNextPage = page.hasNextPage;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(exerciseCatalogProvider).asData?.value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Workout history')),
      body: _error != null
          ? Center(child: Text('Error: $_error'))
          : _workouts.isEmpty && !_loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      const Text('No workouts yet'),
                    ],
                  ),
                )
              : NotificationListener<ScrollEndNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 200) _loadMore();
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _workouts.length + (_hasNextPage ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _workouts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final workout = _workouts[index];
                      return Dismissible(
                        key: ValueKey(workout.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmDelete(context),
                        onDismissed: (_) => _deleteWorkout(workout),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(appCardRadius),
                          ),
                          child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                        ),
                        child: _WorkoutHistoryCard(
                          workout: workout,
                          catalog: catalog,
                          onDelete: () async {
                            if (await _confirmDelete(context)) await _deleteWorkout(workout);
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _WorkoutHistoryCard extends ConsumerWidget {
  const _WorkoutHistoryCard({required this.workout, required this.catalog, required this.onDelete});

  final Workout workout;
  final Map<String, Exercise> catalog;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseNames = {
      for (final set in workout.sets) catalog[set.exerciseId]?.name ?? 'Exercise',
    }.toList();
    final unit = ref.watch(weightUnitProvider);
    final totalVolumeKg = workout.sets
        .where((s) => s.setType != SetType.warmup)
        .fold<double>(0, (sum, s) => sum + s.weightKg * s.reps);
    final displayVolume = unit.fromKg(totalVolumeKg);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _formatDate(workout.startedAt),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${workout.sets.length} set${workout.sets.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share, size: 18),
                  tooltip: 'Share',
                  visualDensity: VisualDensity.compact,
                  onPressed: workout.sets.isEmpty
                      ? null
                      : () => showSharePreview(
                            context,
                            card: WorkoutSummaryShareCard(workout: workout, catalog: catalog, unit: unit),
                            filename: 'workout_${workout.id}',
                          ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            if (exerciseNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                exerciseNames.join(' · '),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (totalVolumeKg > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Volume: ${displayVolume.toStringAsFixed(0)} ${unit.label}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            if (workout.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(workout.notes, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}
