/// Builds the app DB from bundled schema + seed SQL on first open. Works on every
/// platform (web/desktop/mobile) via the sqflite FFI factories.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite_common/sqlite_api.dart';

/// Bump whenever bundled schema/seed data changes: existing installs drop and
/// rebuild their local copy on next launch.
const _dbVersion = 6;

Future<Database> openAppDb(DatabaseFactory factory) async {
  return factory.openDatabase(
    'bestcard.db',
    options: OpenDatabaseOptions(
      version: _dbVersion,
      onCreate: (db, _) async => _build(db),
      onUpgrade: (db, _, __) async {
        await db.execute('PRAGMA foreign_keys = OFF');
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        for (final t in tables) {
          await db.execute('DROP TABLE IF EXISTS ${t['name']}');
        }
        await db.execute('PRAGMA foreign_keys = ON');
        await _build(db);
      },
    ),
  );
}

Future<void> _build(Database db) async {
  await _runScript(db, 'assets/schema.sql');
  await _runScript(db, 'assets/seed.sql');
}

Future<void> _runScript(Database db, String asset) async {
  final sql = await rootBundle.loadString(asset);
  for (final stmt in _statements(sql)) {
    await db.execute(stmt);
  }
}

/// Split a SQL file into executable statements: drop line comments and PRAGMAs
/// (PRAGMA returns a row that the web worker can't marshal), then split on ';'
/// — but only outside string literals, so quoted text may contain semicolons.
Iterable<String> _statements(String sql) => splitSqlStatements(sql);

List<String> splitSqlStatements(String sql) {
  final noComments = sql
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('--') && !t.toUpperCase().startsWith('PRAGMA');
      })
      .join('\n');

  final statements = <String>[];
  final current = StringBuffer();
  var inString = false;
  for (var i = 0; i < noComments.length; i++) {
    final ch = noComments[i];
    if (ch == "'") {
      // In SQL, '' inside a string is an escaped quote, not a terminator.
      inString = !inString;
    }
    if (ch == ';' && !inString) {
      final stmt = current.toString().trim();
      if (stmt.isNotEmpty) statements.add(stmt);
      current.clear();
    } else {
      current.write(ch);
    }
  }
  final last = current.toString().trim();
  if (last.isNotEmpty) statements.add(last);
  return statements;
}
