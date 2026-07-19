/// Picks the right sqflite DatabaseFactory per platform. The conditional import
/// keeps the web build from ever compiling the native (sqflite/ffi) code.
import 'package:sqflite_common/sqlite_api.dart';

import 'db_factory_native.dart'
    if (dart.library.html) 'db_factory_web.dart' as impl;

DatabaseFactory resolveDbFactory() => impl.resolveDbFactory();
