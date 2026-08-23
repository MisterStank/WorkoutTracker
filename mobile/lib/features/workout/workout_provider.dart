import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/storage/recent_exercises_storage.dart';
import '../auth/auth_provider.dart';
import 'workout_models.dart';
import 'workout_repository.dart';
import 'workout_state.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(graphQLClientProvider));
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
  return ActiveWorkoutNotifier(ref.watch(workoutRepositoryProvider));
});

class ActiveWorkoutNotifier extends StateNotifier<ActiveWorkoutState> {
  ActiveWorkoutNotifier(this._repository) : super(const ActiveWorkoutLoading()) {
    refresh();
  }

  final WorkoutRepository _repository;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> refresh() async {
    state = const ActiveWorkoutLoading();
    try {
      final workout = await _repository.activeWorkout();
      state = workout == null ? const ActiveWorkoutNone() : ActiveWorkoutInProgress(workout);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  Future<void> start() async {
    state = const ActiveWorkoutLoading();
    try {
      final workout = await _repository.startWorkout();
      state = ActiveWorkoutInProgress(workout);
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  Future<void> logSet({required String exerciseId, required int reps, required double weightKg, double? rpe}) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;

    try {
      final result = await _repository.logSet(
        workoutId: current.workout.id,
        exerciseId: exerciseId,
        reps: reps,
        weightKg: weightKg,
        rpe: rpe,
      );
      final updatedSets = [...current.workout.sets, result.set];
      final updatedWorkout = Workout(
        id: current.workout.id,
        startedAt: current.workout.startedAt,
        status: current.workout.status,
        notes: current.workout.notes,
        sets: updatedSets,
      );
      state = ActiveWorkoutInProgress(updatedWorkout, lastNewRecords: result.newRecords);

      if (result.newRecords.isNotEmpty) {
        // Auto-dismiss the "new PR" banner rather than leaving it stuck
        // until the next set is logged.
        Future.delayed(const Duration(seconds: 4), () {
          if (_disposed) return;
          final latest = state;
          if (latest is ActiveWorkoutInProgress && identical(latest.lastNewRecords, result.newRecords)) {
            state = ActiveWorkoutInProgress(latest.workout);
          }
        });
      }
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }

  Future<void> finish({String? notes}) async {
    final current = state;
    if (current is! ActiveWorkoutInProgress) return;

    try {
      await _repository.finishWorkout(workoutId: current.workout.id, notes: notes);
      state = const ActiveWorkoutNone();
    } catch (e) {
      state = ActiveWorkoutError(e.toString());
    }
  }
}
