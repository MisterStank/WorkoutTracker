import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/notifications/retention_nudge.dart';

void main() {
  group('nextRetentionNudgeTime', () {
    test('returns null when there is no workout history at all', () {
      expect(nextRetentionNudgeTime(lastWorkoutFinishedAt: null), isNull);
    });

    test('is always exactly retentionNudgeInterval after the last finished workout', () {
      final last = DateTime(2026, 1, 1, 9);
      final next = nextRetentionNudgeTime(lastWorkoutFinishedAt: last);
      expect(next, last.add(retentionNudgeInterval));
    });

    test('does not depend on the current time, only on the last workout', () {
      final last = DateTime(2020, 6, 15);
      final next = nextRetentionNudgeTime(lastWorkoutFinishedAt: last);
      expect(next, DateTime(2020, 6, 18));
    });
  });

  group('isRetentionNudgeStillDue', () {
    test('is due when the nudge time is still in the future', () {
      final now = DateTime(2026, 1, 1);
      final nudgeTime = now.add(const Duration(hours: 2));
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime, now: now), isTrue);
    });

    test('is due when the nudge time is in the past by less than a day', () {
      final now = DateTime(2026, 1, 1, 12);
      final nudgeTime = now.subtract(const Duration(hours: 5));
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime, now: now), isTrue);
    });

    test('is not due once the nudge time is more than a day in the past', () {
      final now = DateTime(2026, 1, 5);
      final nudgeTime = now.subtract(const Duration(days: 2));
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime, now: now), isFalse);
    });

    test('boundary: exactly one day late still counts as not due', () {
      final now = DateTime(2026, 1, 5, 12);
      final nudgeTime = now.subtract(const Duration(days: 1));
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime, now: now), isFalse);
    });
  });

  group('end-to-end scheduling scenarios', () {
    test('a user active yesterday has no reminder due yet', () {
      final now = DateTime(2026, 1, 10);
      final lastWorkout = now.subtract(const Duration(days: 1));
      final nudgeTime = nextRetentionNudgeTime(lastWorkoutFinishedAt: lastWorkout);
      expect(nudgeTime, isNotNull);
      expect(nudgeTime!.isAfter(now), isTrue, reason: 'reminder should still be in the future, not fire immediately');
    });

    test('a user who opens the app a few hours after the interval elapsed still gets nudged', () {
      // Silent for retentionNudgeInterval + 6h — just past due, nowhere near stale.
      final now = DateTime(2026, 1, 10);
      final lastWorkout = now.subtract(retentionNudgeInterval + const Duration(hours: 6));
      final nudgeTime = nextRetentionNudgeTime(lastWorkoutFinishedAt: lastWorkout);
      expect(nudgeTime, isNotNull);
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime!, now: now), isTrue);
    });

    test('a user silent for a full week has a nudge time too stale to bother firing', () {
      // The reminder would have been due 4 days ago — long past the 1-day
      // staleness cutoff, so re-opening now should not fire a very late nudge.
      final now = DateTime(2026, 1, 10);
      final lastWorkout = now.subtract(const Duration(days: 7));
      final nudgeTime = nextRetentionNudgeTime(lastWorkoutFinishedAt: lastWorkout);
      expect(nudgeTime, isNotNull);
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime!, now: now), isFalse);
    });

    test('reopening the app weeks after a stale scheduled nudge does not re-fire it', () {
      final lastWorkout = DateTime(2026, 1, 1);
      final nudgeTime = nextRetentionNudgeTime(lastWorkoutFinishedAt: lastWorkout)!;
      final reopenedMuchLater = DateTime(2026, 2, 1);
      expect(isRetentionNudgeStillDue(nudgeTime: nudgeTime, now: reopenedMuchLater), isFalse);
    });
  });
}
