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
