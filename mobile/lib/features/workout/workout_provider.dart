import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/notifications/retention_nudge_service.dart';
import '../../core/offline/app_database.dart';
import '../../core/offline/offline_provider.dart';
import '../../core/storage/recent_exercises_storage.dart';
import '../auth/auth_provider.dart';
import 'workout_models.dart';
import 'workout_repository.dart';
import 'workout_state.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(graphQLClientProvider));
});

/// Runs once per app session (Riverpod caches FutureProviders): initializes
/// the retention-nudge notification plugin and schedules the reminder from
/// whatever the user's most recent finished workout already was — so the
/// nudge is still correct after an app restart, not just after the next
/// workout finishes (see ActiveWorkoutNotifier.finish for that half).
final retentionNudgeInitProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(retentionNudgeServiceProvider);
  await service.initialize();
  try {
    final page = await ref.watch(workoutRepositoryProvider).workoutHistory(first: 1);
    final mostRecent = page.workouts.isEmpty ? null : page.workouts.first;
    await service.rescheduleFrom(mostRecent?.endedAt);
  } catch (_) {
    // Best-effort — a failed fetch just means the reminder doesn't get
    // (re)scheduled this launch; nothing in the active-workout flow depends
    // on it.
  }
});

final recentExercisesStorageProvider = Provider<RecentExercisesStorage>((ref) {
  return RecentExercisesStorage(const FlutterSecureStorage());
});

/// The full exercise catalog, fetched once and kept as an id-keyed map so
/// any screen can resolve a WorkoutSet's exerciseId to a display name
/// without a network round trip or a per-item dataloader on the client.
final exerciseCatalogProvider = FutureProvider<Map<String, Exercise>>((ref) async {
  final exercises = await ref.watch(workoutRepositoryProvider).exercises();
  return {for (final e in exercises) e.id: e};
});

final recentExerciseIdsProvider = StateNotifierProvider<RecentExerciseIdsNotifier, List<String>>((ref) {
  return RecentExerciseIdsNotifier(ref.watch(recentExercisesStorageProvider));
});

class RecentExerciseIdsNotifier extends StateNotifier<List<String>> {
  RecentExerciseIdsNotifier(this._storage) : super([]) {
    _storage.read().then((ids) => state = ids);
  }

  final RecentExercisesStorage _storage;

  Future<void> recordUse(String exerciseId) async {
    state = await _storage.recordUse(exerciseId);
  }
}

final activeWorkoutProvider = StateNotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState>((ref) {
  return ActiveWorkoutNotifier(ref.watch(workoutRepositoryProvider), ref);
});

class ActiveWorkoutNotifier extends StateNotifier<ActiveWorkoutState> {
  ActiveWorkoutNotifier(this._repository, this._ref) : super(const ActiveWorkoutLoading()) {
    refresh();
  }

  final WorkoutRepository _repository;
  final Ref _ref;
  bool _disposed = false;
  int _localIdCounter = 0;
  StreamSubscription<LogSetResult>? _liveSub;
  String? _liveSubWorkoutId;
  // Every PR earned since the current workout started, for the post-finish
  // completion screen — unlike lastNewRecords (most recent logSet only,
  // auto-cleared after 4s), this survives for the whole session.
  List<PersonalRecord> _sessionRecords = [];

  @override
  void dispose() {
    _disposed = true;
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    state = const ActiveWorkoutLoading();
    _sessionRecords = [];
    try {
      final workout = await _repository.activeWorkout();
      if (workout == null) {
        _stopWatching();
        state = const ActiveWorkoutNone();
      } else {
        state = ActiveWorkoutInProgress(workout);
        _watch(workout.id);
      }
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  Future<void> start({String? templateId}) async {
    state = const ActiveWorkoutLoading();
    _sessionRecords = [];
    try {
      final workout = await _repository.startWorkout(templateId: templateId);
      state = ActiveWorkoutInProgress(workout);
      _watch(workout.id);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  /// Logs a set. If the request fails (most commonly: no connectivity —
  /// there's no dead-gym-wifi indicator otherwise), the set is queued
  /// locally in Drift and shown immediately as "pending" rather than lost;
  /// SyncService pushes it through once connectivity returns.
  Future<void> logSet({
    required String exerciseId,
    required int reps,
    required double weightKg,
    double? rpe,
    SetType setType = SetType.normal,
    String? supersetId,
  }) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;

    try {
      final result = await _repository.logSet(
        workoutId: current.workout.id,
        exerciseId: exerciseId,
        reps: reps,
        weightKg: weightKg,
        rpe: rpe,
        setType: setType,
        supersetId: supersetId,
      );
      _applyLoggedSet(result);
    } catch (e) {
      if (offlineQueueSupported) {
        await _enqueueOffline(
          workoutId: current.workout.id,
          exerciseId: exerciseId,
          reps: reps,
          weightKg: weightKg,
          rpe: rpe,
          setType: setType,
          supersetId: supersetId,
        );
      } else {
        state = ActiveWorkoutError(e.toString());
      }
    }
  }

  Future<void> _enqueueOffline({
    required String workoutId,
    required String exerciseId,
    required int reps,
    required double weightKg,
    double? rpe,
    required SetType setType,
    String? supersetId,
  }) async {
    final localId = '${DateTime.now().microsecondsSinceEpoch}_${_localIdCounter++}';

    final db = _ref.read(appDatabaseProvider);
    await db.enqueue(PendingSetsCompanion.insert(
      localId: localId,
      workoutId: workoutId,
      exerciseId: exerciseId,
      reps: reps,
      weightKg: weightKg,
      rpe: Value(rpe),
      setType: Value(setType.name),
      supersetId: Value(supersetId),
      createdAt: DateTime.now(),
    ));

    final current = state;
    if (current is! ActiveWorkoutInProgress) return;
    final placeholder = WorkoutSet(
      id: _pendingSetId(localId),
      exerciseId: exerciseId,
      setNumber: current.workout.sets.length + 1,
      reps: reps,
      weightKg: weightKg,
      rpe: rpe,
      setType: setType,
      supersetId: supersetId,
      isPending: true,
    );
    final updatedWorkout = Workout(
      id: current.workout.id,
      startedAt: current.workout.startedAt,
      status: current.workout.status,
      notes: current.workout.notes,
      templateId: current.workout.templateId,
      sets: [...current.workout.sets, placeholder],
    );
    state = ActiveWorkoutInProgress(updatedWorkout);
  }

  /// Called by SyncService once a queued set has actually been pushed to
  /// the server: swaps the optimistic placeholder for the real, PR-checked
  /// result.
  void reconcilePendingSet(String localId, LogSetResult result) {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;
    final withoutPlaceholder = current.workout.sets.where((s) => s.id != _pendingSetId(localId)).toList();
    final updatedWorkout = Workout(
      id: current.workout.id,
      startedAt: current.workout.startedAt,
      status: current.workout.status,
      notes: current.workout.notes,
      templateId: current.workout.templateId,
      sets: withoutPlaceholder,
    );
    state = ActiveWorkoutInProgress(updatedWorkout);
    _applyLoggedSet(result);
  }

  String _pendingSetId(String localId) => 'pending-$localId';

  Future<FinishedWorkout?> finish({String? notes}) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return null;

    try {
      final finished = await _repository.finishWorkout(workoutId: current.workout.id, notes: notes);
      final records = _sessionRecords;
      _sessionRecords = [];
      _stopWatching();
      state = const ActiveWorkoutNone();
      unawaited(_ref.read(retentionNudgeServiceProvider).rescheduleFrom(finished.endedAt ?? DateTime.now()));
      return FinishedWorkout(workout: finished, newRecords: records);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
      return null;
    }
  }

  /// Corrects a mis-logged set's reps/weight/RPE/type. Updates local state
  /// from the server's response rather than optimistically, since the
  /// server also recomputes personal records/rollups that the client has
  /// no way to predict.
  Future<void> editSet({
    required String setId,
    required int reps,
    required double weightKg,
    double? rpe,
    SetType setType = SetType.normal,
  }) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;
    try {
      final updated = await _repository.updateSet(setId: setId, reps: reps, weightKg: weightKg, rpe: rpe, setType: setType);
      final updatedWorkout = Workout(
        id: current.workout.id,
        startedAt: current.workout.startedAt,
        status: current.workout.status,
        notes: current.workout.notes,
        templateId: current.workout.templateId,
        sets: [for (final s in current.workout.sets) if (s.id == setId) updated else s],
      );
      state = ActiveWorkoutInProgress(updatedWorkout);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  Future<void> deleteSet(String setId) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;
    try {
      await _repository.deleteSet(setId);
      final updatedWorkout = Workout(
        id: current.workout.id,
        startedAt: current.workout.startedAt,
        status: current.workout.status,
        notes: current.workout.notes,
        templateId: current.workout.templateId,
        sets: current.workout.sets.where((s) => s.id != setId).toList(),
      );
      state = ActiveWorkoutInProgress(updatedWorkout);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  /// Subscribes to live updates for [workoutId] over the GraphQL websocket
  /// (Redis pub/sub server-side) so a set logged from another device/tab
  /// shows up here without polling. Idempotent: re-entering this workout
  /// (e.g. after `refresh`) won't open a second subscription.
  void _watch(String workoutId) {
    if (_liveSubWorkoutId == workoutId) return;
    _stopWatching();
    _liveSubWorkoutId = workoutId;
    // Best-effort real-time sync, same philosophy as logout()'s server-side
    // revoke below: a dropped subscription shouldn't surface an error or
    // crash — the workout stays fully usable via the normal mutations.
    _liveSub = _repository.watchWorkoutProgress(workoutId).listen(_applyLoggedSet, onError: (_) {});
  }

  void _stopWatching() {
    _liveSub?.cancel();
    _liveSub = null;
    _liveSubWorkoutId = null;
  }

  /// Applies a logged set whether it came from this device's own mutation
  /// response or a live subscription event — deduplicated by set id so our
  /// own optimistic update and the subscription echo of it don't double up.
  void _applyLoggedSet(LogSetResult result) {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;
    if (current.workout.sets.any((s) => s.id == result.set.id)) return;

    final updatedWorkout = Workout(
      id: current.workout.id,
      startedAt: current.workout.startedAt,
      status: current.workout.status,
      notes: current.workout.notes,
      templateId: current.workout.templateId,
      sets: [...current.workout.sets, result.set],
    );
    state = ActiveWorkoutInProgress(updatedWorkout, lastNewRecords: result.newRecords);

    if (result.newRecords.isNotEmpty) {
      _sessionRecords = [..._sessionRecords, ...result.newRecords];

      // Auto-dismiss the "new PR" banner rather than leaving it stuck until
      // the next set is logged.
      Future.delayed(const Duration(seconds: 4), () {
        if (_disposed) return;
        final latest = state;
        if (latest is ActiveWorkoutInProgress && identical(latest.lastNewRecords, result.newRecords)) {
          state = ActiveWorkoutInProgress(latest.workout);
        }
      });
    }
  }
}
