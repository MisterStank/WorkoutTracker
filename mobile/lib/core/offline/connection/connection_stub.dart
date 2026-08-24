import 'package:drift/drift.dart';

/// Fallback used when compiling for a platform without dart:io (i.e. web).
/// Offline queueing is a mobile-first feature — gym wifi dropping mid-set is
/// the problem it solves, and that's not a scenario a browser tab needs to
/// handle the same way. Callers must check [offlineQueueSupported] before
/// touching the database on web.
QueryExecutor connect() {
  throw UnsupportedError('Offline storage is not available on this platform.');
}
