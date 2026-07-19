/// Builds the app DB from bundled schema + seed SQL on first open. Works on every
/// platform (web/desktop/mobile) via the sqflite FFI factories.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite_common/sqlite_api.dart';

/// Bump whenever bundled schema/seed data changes: existing installs drop and
/// rebuild their local copy on next launch.
const _dbVersion = 13;

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

Iterable<String> _statements(String sql) => splitSqlStatements(sql);

/// Split a SQL script into executable statements. Char-level tokenizer so it
/// handles `--` comments *anywhere* (including inline, e.g. after a column with
/// an apostrophe in the comment), single-quoted strings with `''` escapes, and
/// semicolons inside string literals. PRAGMA statements are dropped (they
/// return a row the web worker can't marshal, and aren't needed at build time).
List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final cur = StringBuffer();
  var inString = false;
  var inComment = false;

  for (var i = 0; i < sql.length; i++) {
    final ch = sql[i];

    if (inComment) {
      if (ch == '\n') {
        inComment = false;
        cur.write(ch);
      }
      continue;
    }
    if (inString) {
      cur.write(ch);
      if (ch == "'") inString = false; // '' escape re-opens on the next char
      continue;
    }
    if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      inComment = true;
      i++;
      continue;
    }
    if (ch == "'") {
      inString = true;
      cur.write(ch);
      continue;
    }
    if (ch == ';') {
      _addStatement(statements, cur.toString());
      cur.clear();
      continue;
    }
    cur.write(ch);
  }
  _addStatement(statements, cur.toString());
  return statements;
}

void _addStatement(List<String> out, String raw) {
  final s = raw.trim();
  if (s.isEmpty) return;
  if (s.toUpperCase().startsWith('PRAGMA')) return;
  out.add(s);
}
