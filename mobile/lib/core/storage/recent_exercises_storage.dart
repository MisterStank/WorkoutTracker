import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists a small most-recently-used list of exercise IDs so the exercise
/// picker can surface them first, saving a search on every set logged.
/// Reuses secure storage (already a dependency for tokens) rather than
/// pulling in shared_preferences for one small list.
class RecentExercisesStorage {
  RecentExercisesStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'recent_exercise_ids';
  static const _maxEntries = 8;

  Future<List<String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(',');
  }

  /// Moves [exerciseId] to the front, de-duplicating and capping length.
  Future<List<String>> recordUse(String exerciseId) async {
    final current = await read();
    final updated = [exerciseId, ...current.where((id) => id != exerciseId)].take(_maxEntries).toList();
    await _storage.write(key: _key, value: updated.join(','));
    return updated;
  }
}
