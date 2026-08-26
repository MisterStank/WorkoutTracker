import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'retention_nudge.dart';

final retentionNudgeServiceProvider = Provider<RetentionNudgeService>((ref) {
  return RetentionNudgeService();
});

/// Schedules (and reschedules) the single "haven't trained in a while?"
/// local notification. Deliberately just one notification at a time,
/// always pushed out to lastWorkout + [retentionNudgeInterval] — simpler
/// and less naggy than a recurring reminder that fires regardless of
/// whether the user actually needs it.
class RetentionNudgeService {
  static const _nudgeNotificationId = 7301;
  static const _channelId = 'retention_nudge';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Sets up the plugin and requests notification permission. No-op on web
  /// (flutter_local_notifications doesn't support scheduled notifications
  /// there) and safe to call more than once — only the first call does
  /// anything.
  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings, macOS: iosSettings),
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Cancels any pending nudge and, if [lastWorkoutFinishedAt] is non-null,
  /// schedules a fresh one at lastWorkoutFinishedAt + [retentionNudgeInterval].
  /// Call this after every finished workout and once on app launch so the
  /// reminder always reflects the user's actual latest activity.
  Future<void> rescheduleFrom(DateTime? lastWorkoutFinishedAt) async {
    if (kIsWeb) return;
    await _plugin.cancel(_nudgeNotificationId);

    final nudgeAt = nextRetentionNudgeTime(lastWorkoutFinishedAt: lastWorkoutFinishedAt);
    if (nudgeAt == null || !isRetentionNudgeStillDue(nudgeTime: nudgeAt, now: DateTime.now())) return;

    await initialize();
    await _plugin.zonedSchedule(
      _nudgeNotificationId,
      'Time for a workout?',
      "It's been a few days since your last session — a quick one still counts.",
      tz.TZDateTime.from(nudgeAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Training reminders',
          channelDescription: 'Reminds you to train after a few days without a logged workout',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
