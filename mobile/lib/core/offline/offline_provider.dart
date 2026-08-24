import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Single AppDatabase instance for the app's lifetime. Only touch this when
/// [offlineQueueSupported] is true (guarded by callers) — on web it throws.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
