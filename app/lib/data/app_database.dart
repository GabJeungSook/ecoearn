import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync_id.dart';

/// Opens the app's SQLite database and creates or upgrades its tables.
class AppDatabase {
  static const fileName = 'ecoearn.db';
  static const _version = 3;

  /// Points rate before it became a setting (firmware GRAMS_PER_POINT).
  static const defaultGramsPerPoint = 10;

  /// %APPDATA%\com.ecoearn\ecoearn_app\ecoearn.db
  static Future<String> defaultPath() async =>
      p.join((await getApplicationSupportDirectory()).path, fileName);

  /// Pass [inMemoryDatabasePath] for a throwaway database (tests).
  static Future<Database> open(String path) {
    sqfliteFfiInit();
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
  }

  // Each schema version adds its changes in its own `if` block, so an old
  // database is upgraded step by step. Never edit a block that has shipped.
  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      await db.execute('''
        CREATE TABLE students (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          student_no    TEXT NOT NULL UNIQUE,
          name          TEXT NOT NULL,
          grade_section TEXT NOT NULL DEFAULT '',
          rfid_uid      TEXT UNIQUE,
          created_at    TEXT NOT NULL
        )''');
      // One row per bottle the machine processed, accepted or rejected.
      await db.execute('''
        CREATE TABLE deposits (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          occurred_at   TEXT NOT NULL,
          rfid_uid      TEXT NOT NULL,
          student_id    INTEGER REFERENCES students(id),
          grams         REAL NOT NULL,
          points        INTEGER NOT NULL,
          reject_reason TEXT,
          source        TEXT NOT NULL DEFAULT 'live'
        )''');
      await db.execute('CREATE INDEX deposits_student ON deposits(student_id)');
      await db.execute('CREATE INDEX deposits_occurred ON deposits(occurred_at)');
    }
    if (from < 2) {
      // Login accounts. Never included in the data file exported for officers.
      await db.execute('''
        CREATE TABLE accounts (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          username      TEXT NOT NULL UNIQUE,
          display_name  TEXT NOT NULL,
          role          TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          created_at    TEXT NOT NULL
        )''');
    }
    if (from < 3) {
      // sync_id: permanent unique ID, so officer imports can merge without duplicates.
      // grams_per_point: the points rate a deposit was earned at (old rows: the old default).
      await db.execute('ALTER TABLE students ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE deposits ADD COLUMN sync_id TEXT');
      await db.execute('ALTER TABLE deposits ADD COLUMN grams_per_point INTEGER');
      for (final table in ['students', 'deposits']) {
        for (final row in await db.query(table, columns: ['id'])) {
          await db.update(table, {'sync_id': newSyncId()}, where: 'id = ?', whereArgs: [row['id']]);
        }
      }
      await db.update('deposits', {'grams_per_point': defaultGramsPerPoint});
      await db.execute('CREATE UNIQUE INDEX students_sync ON students(sync_id)');
      await db.execute('CREATE UNIQUE INDEX deposits_sync ON deposits(sync_id)');

      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      await db.insert('settings', {'key': 'grams_per_point', 'value': '$defaultGramsPerPoint'});
      // Every change of the points rate, for the record.
      await db.execute('''
        CREATE TABLE point_rate_changes (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          changed_at      TEXT NOT NULL,
          grams_per_point INTEGER NOT NULL,
          changed_by      TEXT NOT NULL DEFAULT ''
        )''');
    }
  }
}
