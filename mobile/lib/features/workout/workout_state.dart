import 'workout_models.dart';

/// Sealed state for the active-workout screen, mirroring the AuthState
/// pattern: a small closed set of states the UI can exhaustively switch on.
sealed class ActiveWorkoutState {
  const ActiveWorkoutState();
}

class ActiveWorkoutLoading extends ActiveWorkoutState {
  const ActiveWorkoutLoading();
}

/// No workout currently in progress.
class ActiveWorkoutNone extends ActiveWorkoutState {
  const ActiveWorkoutNone();
}

class ActiveWorkoutInProgress extends ActiveWorkoutState {
  const ActiveWorkoutInProgress(this.workout, {this.lastNewRecords = const []});

  final Workout workout;
  // Surfaced briefly after logSet so the UI can show a "new PR!" banner.
  final List<PersonalRecord> lastNewRecords;
}

class ActiveWorkoutError extends ActiveWorkoutState {
  const ActiveWorkoutError(this.message);

  final String message;
}

/// The result of ActiveWorkoutNotifier.finish(): the authoritative finished
/// Workout (real endedAt/COMPLETED status from the server, not a pre-finish
/// local snapshot) plus every PR earned across the whole session — unlike
/// ActiveWorkoutInProgress.lastNewRecords, which only ever holds the most
/// recent logSet's PRs and auto-clears after a few seconds.
class FinishedWorkout {
  const FinishedWorkout({required this.workout, required this.newRecords});

  final Workout workout;
  final List<PersonalRecord> newRecords;
}
