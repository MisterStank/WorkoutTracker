/// Pure scheduling logic for the "haven't trained in a while?" reminder —
/// kept free of any plugin/platform dependency so it's trivially unit
/// testable. [RetentionNudgeService] (retention_nudge_service.dart) is the
/// thin platform wrapper that actually schedules a local notification at
/// the time this returns.
library;

/// How long without a finished workout before a reminder is due.
const retentionNudgeInterval = Duration(days: 3);

/// The next moment a reminder should fire, or null if none is warranted
/// right now (no workout history at all — wait for the first one before
/// nagging someone who hasn't started using the app yet).
///
/// Always [retentionNudgeInterval] after the last finished workout,
/// regardless of "now" — the caller re-schedules this every time a workout
/// finishes or the app launches, so it's always correct.
DateTime? nextRetentionNudgeTime({required DateTime? lastWorkoutFinishedAt}) {
  if (lastWorkoutFinishedAt == null) return null;
  return lastWorkoutFinishedAt.add(retentionNudgeInterval);
}

/// Whether a reminder scheduled for [nudgeTime] is still worth firing —
/// false if it's already in the past by more than a day (the app was
/// closed through the whole window; firing a stale reminder days late on
/// next launch would be more annoying than useful).
bool isRetentionNudgeStillDue({required DateTime nudgeTime, required DateTime now}) {
  return nudgeTime.isAfter(now.subtract(const Duration(days: 1)));
}
