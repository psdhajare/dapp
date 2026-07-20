import 'dart:io';

import 'package:bestcard/app_db.dart' show splitSqlStatements;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds an in-memory DB from the shared schema + seed SQL (same content the app
/// bundles), so tests exercise the real schema.
///
/// The ffi factory shares one ':memory:' DB across opens within a test run, so
/// drop leftover tables from previous tests before rebuilding.
Future<Database> openSeedDb() async {
  sqfliteFfiInit();
  // No-isolate factory: the isolate-backed one leaves a background worker alive
  // that keeps `testWidgets` from terminating (hangs at teardown).
  final db =
      await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
  await db.execute('PRAGMA foreign_keys = OFF');
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  );
  for (final t in tables) {
    await db.execute('DROP TABLE IF EXISTS ${t['name']}');
  }
  await db.execute('PRAGMA foreign_keys = ON');
  await _runFile(db, '../db/schema.sql');
  await _runFile(db, '../db/seed.sql');
  return db;
}

Future<void> _runFile(Database db, String path) async {
  final sql = File(path).readAsStringSync();
  for (final stmt in splitSqlStatements(sql)) {
    await db.execute(stmt);
  }
}
