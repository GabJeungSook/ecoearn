import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync_id.dart';

/// Opens the app's SQLite database and creates or upgrades its tables.
class AppDatabase {
  static const fileName = 'ecoearn.db';
  static const _version = 4;

  /// Points rate before it became a setting (firmware GRAMS_PER_POINT).
  static const defaultGramsPerPoint = 10;

  /// Peso value of one point when paying fees, until the admin or an officer changes it.
  static const defaultPesosPerPoint = 1.0;

  /// Fees, payments and the peso rate (schema v4). IF NOT EXISTS, so it can also
  /// bring an officer's data copied from an older export up to date.
  static Future<void> createFeeTables(DatabaseExecutor db) async {
    // Fees students can pay with points. Never deleted (old payments name them): archived with active = 0.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fees (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id    TEXT UNIQUE,
        name       TEXT NOT NULL,
        amount     REAL NOT NULL,
        active     INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      )''');
    // A fee paid in full with points (made on the officer's computer). Voided, never deleted.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_id         TEXT UNIQUE,
        student_id      INTEGER NOT NULL REFERENCES students(id),
        fee_name        TEXT NOT NULL,
        amount          REAL NOT NULL,
        points          INTEGER NOT NULL,
        pesos_per_point REAL NOT NULL,
        paid_at         TEXT NOT NULL,
        processed_by    TEXT NOT NULL DEFAULT '',
        voided_at       TEXT,
        void_reason     TEXT,
        voided_by       TEXT
      )''');
    await db.execute('CREATE INDEX IF NOT EXISTS payments_student ON payments(student_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS peso_rate_changes (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        changed_at      TEXT NOT NULL,
        pesos_per_point REAL NOT NULL,
        changed_by      TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await db.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('pesos_per_point', '$defaultPesosPerPoint')");
    // When the rate last changed, so a merge keeps the newest one.
    await db.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('pesos_per_point_changed_at', '')");
  }

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
    if (from < 4) await createFeeTables(db);
  }
}
