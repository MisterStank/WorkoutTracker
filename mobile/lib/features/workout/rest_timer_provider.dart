import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/notifications/retention_nudge_service.dart';

/// A simple rest-timer countdown, started after each set is logged. Kept as
/// plain in-memory Riverpod state (no persistence of the countdown itself —
/// a rest timer that survives an app restart isn't meaningful), but the
/// *default duration* the user prefers is persisted.
class RestTimerState {
  const RestTimerState({required this.remaining, required this.total, required this.running});

  final Duration remaining;
  final Duration total;
  final bool running;

  static const idle = RestTimerState(remaining: Duration.zero, total: Duration.zero, running: false);
}

const _restDurationKey = 'rest_timer_default_seconds';
const _defaultRestSeconds = 90;

final restTimerProvider = StateNotifierProvider<RestTimerNotifier, RestTimerState>((ref) {
  return RestTimerNotifier(ref.read(retentionNudgeServiceProvider));
});

class RestTimerNotifier extends StateNotifier<RestTimerState> {
  RestTimerNotifier(this._notifications) : super(RestTimerState.idle) {
    _loadDefault();
  }

  final RetentionNudgeService _notifications;
  final _storage = const FlutterSecureStorage();

  Timer? _ticker;
  Duration _defaultDuration = const Duration(seconds: _defaultRestSeconds);
  // Wall-clock instant the current rest ends. Remaining time is always
  // computed from this rather than decremented, so navigating away or
  // backgrounding the app (which suspends the ticker) doesn't drift the
  // countdown — it self-corrects on the next tick / on resume().
  DateTime? _endsAt;

  Duration get defaultDuration => _defaultDuration;

  Future<void> _loadDefault() async {
    try {
      final raw = await _storage.read(key: _restDurationKey);
      final secs = int.tryParse(raw ?? '');
      if (secs != null && secs >= 15 && secs <= 600) {
        _defaultDuration = Duration(seconds: secs);
      }
    } catch (_) {
      // Keep the built-in default.
    }
  }

  /// Sets and persists the duration used when no explicit one is passed to
  /// [start] — e.g. from a settings control.
  Future<void> setDefault(Duration duration) async {
    _defaultDuration = duration;
    try {
      await _storage.write(key: _restDurationKey, value: duration.inSeconds.toString());
    } catch (_) {}
  }

  void start([Duration? duration]) {
    final total = duration ?? _defaultDuration;
    _ticker?.cancel();
    _endsAt = DateTime.now().add(total);
    state = RestTimerState(remaining: total, total: total, running: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final remaining = endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _ticker?.cancel();
      _endsAt = null;
      state = RestTimerState(remaining: Duration.zero, total: state.total, running: false);
      _notifications.showRestComplete();
    } else {
      state = RestTimerState(remaining: remaining, total: state.total, running: true);
    }
  }

  /// Recomputes the countdown from the wall clock — call when the app
  /// returns to the foreground, in case the ticker was suspended.
  void resume() {
    if (state.running) _tick();
  }

  void addSeconds(int seconds) {
    if (!state.running || _endsAt == null) return;
    _endsAt = _endsAt!.add(Duration(seconds: seconds));
    final total = state.total + Duration(seconds: seconds);
    state = RestTimerState(remaining: _endsAt!.difference(DateTime.now()), total: total, running: true);
  }

  void skip() {
    _ticker?.cancel();
    _endsAt = null;
    state = RestTimerState.idle;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
