import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'workout_models.dart';
import 'workout_repository.dart';
import 'workout_state.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(graphQLClientProvider));
});

final activeWorkoutProvider = StateNotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState>((ref) {
  return ActiveWorkoutNotifier(ref.watch(workoutRepositoryProvider));
});

class ActiveWorkoutNotifier extends StateNotifier<ActiveWorkoutState> {
  ActiveWorkoutNotifier(this._repository) : super(const ActiveWorkoutLoading()) {
    refresh();
  }

  final WorkoutRepository _repository;

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
