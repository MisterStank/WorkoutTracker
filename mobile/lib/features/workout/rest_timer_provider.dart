import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A simple rest-timer countdown, started after each set is logged. Kept as
/// plain in-memory Riverpod state (no persistence needed — a rest timer
/// that survives an app restart isn't meaningful).
class RestTimerState {
  const RestTimerState({required this.remaining, required this.total, required this.running});

  final Duration remaining;
  final Duration total;
  final bool running;

  static const idle = RestTimerState(remaining: Duration.zero, total: Duration.zero, running: false);
}

final restTimerProvider = StateNotifierProvider<RestTimerNotifier, RestTimerState>((ref) {
  return RestTimerNotifier();
});

class RestTimerNotifier extends StateNotifier<RestTimerState> {
  RestTimerNotifier() : super(RestTimerState.idle);

  Timer? _ticker;
  Duration _lastDuration = const Duration(seconds: 90);

  void start([Duration? duration]) {
    final total = duration ?? _lastDuration;
    _lastDuration = total;
    _ticker?.cancel();
    state = RestTimerState(remaining: total, total: total, running: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = state.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _ticker?.cancel();
        state = RestTimerState(remaining: Duration.zero, total: state.total, running: false);
      } else {
        state = RestTimerState(remaining: next, total: state.total, running: true);
      }
    });
  }

  void addSeconds(int seconds) {
    if (!state.running) return;
    final next = state.remaining + Duration(seconds: seconds);
    state = RestTimerState(remaining: next < Duration.zero ? Duration.zero : next, total: state.total, running: true);
  }

  void skip() {
    _ticker?.cancel();
    state = RestTimerState.idle;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
