import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'connection/connection_stub.dart' if (dart.library.io) 'connection/connection_native.dart' as impl;

part 'app_database.g.dart';

/// Whether this platform can persist an offline outbox at all. False on web
/// (no dart:io/sqlite3 native binding without extra wasm setup) — offline
/// queueing degrades to "just show the error" there, same as before this
/// feature existed.
const offlineQueueSupported = !kIsWeb;

/// One set logged while offline, waiting to be pushed to the server. Kept
/// deliberately narrow — just what logSet needs — rather than a general
/// sync-everything outbox, since set logging during an active workout is
/// the one write that actually happens at the gym with bad signal.
class PendingSets extends Table {
  TextColumn get localId => text()();
  TextColumn get workoutId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get reps => integer()();
  RealColumn get weightKg => real()();
  RealColumn get rpe => real().nullable()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

@DriftDatabase(tables: [PendingSets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(impl.connect());

  @override
  int get schemaVersion => 1;

  Future<List<PendingSet>> allPendingOldestFirst() =>
      (select(pendingSets)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<void> enqueue(PendingSetsCompanion entry) => into(pendingSets).insert(entry);

  Future<void> removePending(String localId) => (delete(pendingSets)..where((t) => t.localId.equals(localId))).go();

  Stream<int> watchPendingCount() =>
      (selectOnly(pendingSets)..addColumns([pendingSets.localId.count()]))
          .map((row) => row.read(pendingSets.localId.count()) ?? 0)
          .watchSingle();
}
