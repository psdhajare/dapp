/// Web: sqflite over the sqlite3 wasm worker.
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

DatabaseFactory resolveDbFactory() => databaseFactoryFfiWeb;
