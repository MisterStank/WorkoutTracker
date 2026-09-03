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
  TextColumn get setType => text().withDefault(const Constant('normal'))();
  TextColumn get supersetId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// A read-only snapshot of the user's pet, so the pet home screen — the
/// app's landing screen — can render offline from the last-known state
/// instead of a spinner or an error. Exactly one row (id = 'me'); the JSON
/// is the full `pet { ... }` GraphQL selection. Purely a cache: the server
/// recomputes mood/streak/unlocks on every online read, so a stale snapshot
/// is only ever shown until the next successful fetch.
class PetCache extends Table {
  TextColumn get id => text()();
  TextColumn get petJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [PendingSets, PetCache])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(impl.connect());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // Both tables hold only transient data the server has (or will have)
        // a durable copy of — the offline outbox's not-yet-synced writes sit
        // on the device that made them, and the pet cache is a throwaway
        // snapshot. So a schema bump just drops and recreates them.
        onUpgrade: (m, from, to) async {
          await m.deleteTable(pendingSets.actualTableName);
          await m.createTable(pendingSets);
          if (from < 3) {
            await m.createTable(petCache);
          }
        },
      );

  Future<void> savePetSnapshot(String petJson) => into(petCache).insertOnConflictUpdate(
        PetCacheCompanion.insert(id: 'me', petJson: petJson, updatedAt: DateTime.now()),
      );

  Future<String?> readPetSnapshot() async {
    final row = await (select(petCache)..where((t) => t.id.equals('me'))).getSingleOrNull();
    return row?.petJson;
  }

  Future<void> clearPetSnapshot() => (delete(petCache)..where((t) => t.id.equals('me'))).go();

  Future<List<PendingSet>> allPendingOldestFirst() =>
      (select(pendingSets)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  Future<void> enqueue(PendingSetsCompanion entry) => into(pendingSets).insert(entry);

  Future<void> removePending(String localId) => (delete(pendingSets)..where((t) => t.localId.equals(localId))).go();

  Stream<int> watchPendingCount() =>
      (selectOnly(pendingSets)..addColumns([pendingSets.localId.count()]))
          .map((row) => row.read(pendingSets.localId.count()) ?? 0)
          .watchSingle();
}
