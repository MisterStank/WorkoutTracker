import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/workout/workout_models.dart' show SetType;
import '../../features/workout/workout_provider.dart';
import 'app_database.dart';
import 'offline_provider.dart';

/// Drains the offline outbox (sets logged while there was no connection)
/// whenever connectivity returns, pushing each through the normal logSet
/// mutation in the order they were recorded. One failure (still offline, or
/// a real server error) stops the flush for this pass — retried on the next
/// connectivity change rather than looping immediately, since a server
/// error retried in a tight loop wouldn't resolve itself.
class SyncService {
  SyncService(this._ref) {
    if (!offlineQueueSupported) return;
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        flush();
      }
    });
    flush();
  }

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _flushing = false;

  Future<void> flush() async {
    if (!offlineQueueSupported || _flushing) return;
    _flushing = true;
    try {
      final db = _ref.read(appDatabaseProvider);
      final repo = _ref.read(workoutRepositoryProvider);
      final pending = await db.allPendingOldestFirst();

      for (final p in pending) {
        try {
          final result = await repo.logSet(
            workoutId: p.workoutId,
            exerciseId: p.exerciseId,
            reps: p.reps,
            weightKg: p.weightKg,
            rpe: p.rpe,
            setType: SetType.values.firstWhere((t) => t.name == p.setType, orElse: () => SetType.normal),
            supersetId: p.supersetId,
          );
          await db.removePending(p.localId);
          _ref.read(activeWorkoutProvider.notifier).reconcilePendingSet(p.localId, result);
        } catch (_) {
          return; // still offline or a real error — try again next connectivity change
        }
      }
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});
