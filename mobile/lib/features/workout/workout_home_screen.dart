import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/app_database.dart' show offlineQueueSupported;
import '../../core/offline/sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart' show appCardRadius;
import '../../core/theme/theme_mode_provider.dart';
import '../../core/units/units_provider.dart';
import '../../core/units/weight_unit.dart';
import '../../core/widgets/semantic_banner.dart';
import '../auth/auth_provider.dart';
import '../programs/fitness_profile_models.dart';
import '../programs/fitness_profile_provider.dart';
import '../sharing/pr_share_card.dart';
import '../sharing/share_preview_sheet.dart';
import '../templates/template_models.dart';
import '../templates/template_provider.dart';
import '../templates/templates_screen.dart';
import 'elapsed_time_text.dart';
import 'exercise_picker_screen.dart';
import 'log_set_sheet.dart';
import 'rest_timer_provider.dart';
import 'superset_provider.dart';
import 'workout_completion_screen.dart';
import 'workout_models.dart';
import 'workout_provider.dart';
import 'workout_state.dart';

enum _OverflowAction { themeSystem, themeLight, themeDark, logout }
enum _SetAction { edit, delete }

class WorkoutHomeScreen extends ConsumerWidget {
  const WorkoutHomeScreen({super.key});

  Future<void> _logNewSet(BuildContext context, WidgetRef ref) async {
    final exercise = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen()),
    );
    if (exercise == null || !context.mounted) return;
    await _logSetForExercise(context, ref, exercise);
  }

  /// Lets the user pick two or more exercises to alternate between mid-workout
  /// (an ad-hoc superset, as opposed to one planned in advance via a
  /// template). Purely client-side bookkeeping — supersetId is attached to
  /// each logged set automatically from then on for those exercises.
  Future<void> _groupSuperset(BuildContext context, WidgetRef ref) async {
    final selected = await Navigator.of(context).push<List<Exercise>>(
      MaterialPageRoute(builder: (_) => const ExercisePickerScreen(multiSelect: true)),
    );
    if (selected == null || selected.length < 2) return;
    ref.read(activeSupersetsProvider.notifier).group(selected.map((e) => e.id).toList());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Grouped ${selected.map((e) => e.name).join(' + ')} as a superset')),
    );
  }

  static Future<void> _logSetForExercise(BuildContext context, WidgetRef ref, Exercise exercise) async {
    final unit = ref.read(weightUnitProvider);
    final repository = ref.read(workoutRepositoryProvider);
    final lastSet = await repository.lastSetForExercise(exercise.id);
    // RPE-based suggestion only makes sense once there's a prior RPE'd set —
    // failures here (e.g. offline) just fall back to no suggestion.
    ProgressionSuggestion? suggestion;
    try {
      suggestion = await repository.progressionSuggestion(exercise.id);
    } catch (_) {
      suggestion = null;
    }
    if (!context.mounted) return;

    final input = await showLogSetSheet(context, exercise, lastSet: lastSet, unit: unit, suggestion: suggestion);
    if (input == null) return;

    final supersetId = ref.read(activeSupersetsProvider.notifier).supersetIdFor(exercise.id);
    await ref.read(activeWorkoutProvider.notifier).logSet(
          exerciseId: exercise.id,
          reps: input.reps,
          weightKg: input.weightKg,
          rpe: input.rpe,
          setType: input.setType,
          supersetId: supersetId,
        );
    ref.read(restTimerProvider.notifier).start();
  }

  static Future<void> _editSet(BuildContext context, WidgetRef ref, Exercise exercise, WorkoutSet set) async {
    final unit = ref.read(weightUnitProvider);
    final input = await showLogSetSheet(context, exercise, editing: set, unit: unit);
    if (input == null) return;
    await ref.read(activeWorkoutProvider.notifier).editSet(
          setId: set.id,
          reps: input.reps,
          weightKg: input.weightKg,
          rpe: input.rpe,
          setType: input.setType,
        );
  }

  static Future<void> _deleteSet(BuildContext context, WidgetRef ref, WorkoutSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete set?'),
        content: Text('This removes set ${set.setNumber} — ${set.reps} reps × ${set.weightKg.toStringAsFixed(set.weightKg.truncateToDouble() == set.weightKg ? 0 : 1)} kg.'),
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
    if (confirmed != true) return;
    await ref.read(activeWorkoutProvider.notifier).deleteSet(set.id);
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
      ref.read(activeSupersetsProvider.notifier).reset();
      await ref.read(activeWorkoutProvider.notifier).start();
    } else if (choice == 'template') {
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplatesScreen()));
      }
    }
  }

  static Future<void> _startFromTemplate(BuildContext context, WidgetRef ref, String templateId) async {
    ref.read(activeSupersetsProvider.notifier).reset();
    await ref.read(activeWorkoutProvider.notifier).start(templateId: templateId);
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

    final result = await ref.read(activeWorkoutProvider.notifier).finish(notes: notes.isEmpty ? null : notes);
    ref.read(activeSupersetsProvider.notifier).reset();

    if (result == null || result.workout.sets.isEmpty || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WorkoutCompletionScreen(workout: result.workout, newRecords: result.newRecords)),
    );
  }

  void _handleOverflowAction(BuildContext context, WidgetRef ref, _OverflowAction action) {
    switch (action) {
      case _OverflowAction.themeSystem:
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.system);
      case _OverflowAction.themeLight:
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      case _OverflowAction.themeDark:
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      case _OverflowAction.logout:
        ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeWorkoutProvider);
    final unit = ref.watch(weightUnitProvider);
    // Keeps SyncService alive for as long as the home screen is mounted, so
    // queued offline sets get pushed as soon as connectivity returns even
    // if the user never re-opens the active-workout screen themselves.
    if (offlineQueueSupported) ref.watch(syncServiceProvider);
    // Fire-and-forget: (re)schedules the retention nudge from the user's
    // actual most recent workout on every app launch.
    ref.watch(retentionNudgeInitProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('WorkoutTracker'),
        actions: [
          TextButton(
            onPressed: () => ref.read(weightUnitProvider.notifier).toggle(),
            child: Text(unit.label.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (state is ActiveWorkoutInProgress)
            IconButton(
              icon: const Icon(Icons.link),
              tooltip: 'Group as superset',
              onPressed: () => _groupSuperset(context, ref),
            ),
          PopupMenuButton<_OverflowAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (action) => _handleOverflowAction(context, ref, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: Text('Theme', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              const PopupMenuItem(value: _OverflowAction.themeSystem, child: Text('System')),
              const PopupMenuItem(value: _OverflowAction.themeLight, child: Text('Light')),
              const PopupMenuItem(value: _OverflowAction.themeDark, child: Text('Dark')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: _OverflowAction.logout, child: Text('Log out')),
            ],
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

class _StartWorkoutView extends ConsumerStatefulWidget {
  const _StartWorkoutView({required this.onStart});

  final VoidCallback onStart;

  @override
  ConsumerState<_StartWorkoutView> createState() => _StartWorkoutViewState();
}

class _StartWorkoutViewState extends ConsumerState<_StartWorkoutView> {
  late Future<NextWorkout?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(fitnessProfileRepositoryProvider).nextWorkout();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FutureBuilder<NextWorkout?>(
              future: _future,
              builder: (context, snapshot) {
                final next = snapshot.data;
                if (next == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _ContinueProgramCard(next: next),
                );
              },
            ),
            FilledButton.icon(
              onPressed: widget.onStart,
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

class _ContinueProgramCard extends ConsumerWidget {
  const _ContinueProgramCard({required this.next});

  final NextWorkout next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(appCardRadius),
        onTap: () => WorkoutHomeScreen._startFromTemplate(context, ref, next.day.template.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                next.program.name,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.play_circle_fill, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Continue: ${next.day.dayLabel}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

    // Template-based workouts show every planned exercise as a card right
    // away (empty until logged), not just once a set exists — closer to how
    // Hevy shows the whole plan up front rather than building it up
    // set-by-set. A blank workout has no plan to pre-populate from, so it
    // keeps the old behavior: cards only appear once something's logged.
    final cardExerciseIds = <String>[];
    if (template != null) {
      for (final te in template.exercises) {
        cardExerciseIds.add(te.exerciseId);
      }
      for (final exerciseId in groups.keys) {
        if (!cardExerciseIds.contains(exerciseId)) cardExerciseIds.add(exerciseId);
      }
    } else {
      cardExerciseIds.addAll(groups.keys);
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
                  ElapsedTimeText(startedAt: workout.startedAt),
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
        if (lastNewRecords.isNotEmpty)
          _NewRecordBanner(
            records: lastNewRecords,
            exerciseName: catalog[lastNewRecords.first.exerciseId]?.name ?? 'Exercise',
            unit: ref.watch(weightUnitProvider),
          ),
        const _RestTimerBanner(),
        Expanded(
          child: cardExerciseIds.isEmpty
              ? const _EmptyWorkoutHint()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: cardExerciseIds.map((exerciseId) {
                    final sets = groups[exerciseId] ?? const <WorkoutSet>[];
                    final exercise = catalog[exerciseId];
                    return _ExerciseGroupCard(
                      exerciseName: exercise?.name ?? 'Exercise',
                      sets: sets,
                      unit: ref.watch(weightUnitProvider),
                      onAddSet: exercise == null ? null : () => WorkoutHomeScreen._logSetForExercise(context, ref, exercise),
                      onRepeatLast: sets.isEmpty
                          ? null
                          : () {
                              final last = sets.last;
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
                      onEditSet: exercise == null ? (_) {} : (set) => WorkoutHomeScreen._editSet(context, ref, exercise, set),
                      onDeleteSet: (set) => WorkoutHomeScreen._deleteSet(context, ref, set),
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
                  ? Icon(Icons.check_circle, size: 16, color: context.semanticColors.success)
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.playlist_add, size: 48, color: muted),
          const SizedBox(height: 8),
          const Text('No sets logged yet'),
          const SizedBox(height: 4),
          Text('Tap "Log set" to add your first one.', style: TextStyle(color: muted)),
        ],
      ),
    );
  }
}

class _NewRecordBanner extends StatelessWidget {
  const _NewRecordBanner({required this.records, required this.exerciseName, required this.unit});

  final List<PersonalRecord> records;
  final String exerciseName;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final labels = records.map((r) => recordTypeLabels[r.recordType] ?? r.recordType).join(' & ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SemanticBanner.success(
        context,
        message: 'New personal record — $labels!',
        trailing: IconButton(
          icon: const Icon(Icons.ios_share, size: 18),
          tooltip: 'Share',
          onPressed: () => showSharePreview(
            context,
            card: PrShareCard(exerciseName: exerciseName, records: records, unit: unit),
            filename: 'pr_$exerciseName',
          ),
        ),
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
    final semantic = context.semanticColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: semantic.infoContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: progress, strokeWidth: 3, color: semantic.info),
              Icon(Icons.timer, size: 14, color: semantic.onInfoContainer),
            ]),
          ),
          const SizedBox(width: 10),
          Text(
            'Rest: ${_format(timer.remaining)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: semantic.onInfoContainer),
          ),
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

(Color, Color) _setTypeColors(SetType type, BuildContext context) {
  final semantic = context.semanticColors;
  return switch (type) {
    SetType.warmup => (semantic.setWarmupContainer, semantic.onSetWarmupContainer),
    SetType.dropset => (semantic.setDropsetContainer, semantic.onSetDropsetContainer),
    SetType.failure => (semantic.setFailureContainer, semantic.onSetFailureContainer),
    SetType.normal => (Colors.transparent, Theme.of(context).colorScheme.onSurface),
  };
}

class _ExerciseGroupCard extends StatelessWidget {
  const _ExerciseGroupCard({
    required this.exerciseName,
    required this.sets,
    required this.unit,
    required this.onRepeatLast,
    required this.onAddSet,
    required this.onEditSet,
    required this.onDeleteSet,
  });

  final String exerciseName;
  final List<WorkoutSet> sets;
  final WeightUnit unit;
  // Null when there's no prior set to repeat (the card is still empty).
  final VoidCallback? onRepeatLast;
  // Null only if the exercise isn't in the catalog yet (shouldn't normally
  // happen) — logs the exercise's first set via the usual set sheet.
  final VoidCallback? onAddSet;
  final void Function(WorkoutSet set) onEditSet;
  final void Function(WorkoutSet set) onDeleteSet;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: const EdgeInsets.only(bottom: 10),
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
                sets.isEmpty
                    ? TextButton.icon(
                        onPressed: onAddSet,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add set'),
                      )
                    : TextButton.icon(
                        onPressed: onRepeatLast,
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Repeat last'),
                      ),
              ],
            ),
            if (sets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  'No sets logged yet',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ...sets.map((set) {
              final displayWeight = unit.fromKg(set.weightKg);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${set.setNumber}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    Text('${set.reps} reps', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 10),
                    Text('×', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 10),
                    Text(
                      '${displayWeight.toStringAsFixed(displayWeight.truncateToDouble() == displayWeight ? 0 : 1)} ${unit.label}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (set.setType != SetType.normal) ...[
                      const SizedBox(width: 8),
                      Builder(builder: (context) {
                        final (bg, fg) = _setTypeColors(set.setType, context);
                        return Tooltip(
                          message: set.setType.label,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
                            child: Text(set.setType.badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
                          ),
                        );
                      }),
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
                        child: Icon(Icons.cloud_off, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const Spacer(),
                    if (!set.isPending)
                      PopupMenuButton<_SetAction>(
                        icon: Icon(Icons.more_vert, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        padding: EdgeInsets.zero,
                        onSelected: (action) {
                          switch (action) {
                            case _SetAction.edit:
                              onEditSet(set);
                            case _SetAction.delete:
                              onDeleteSet(set);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: _SetAction.edit, child: Text('Edit')),
                          PopupMenuItem(value: _SetAction.delete, child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );

    if (sets.isEmpty && onAddSet != null) {
      // The whole card is a tap target while it's still empty — matches the
      // chip-row's existing behavior and avoids making "Add set" the only
      // way in.
      return InkWell(borderRadius: BorderRadius.circular(appCardRadius), onTap: onAddSet, child: card);
    }
    return card;
  }
}

