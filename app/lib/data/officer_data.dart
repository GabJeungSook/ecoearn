import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'reports.dart';
import 'student_repository.dart';

/// The data file the admin exports for officers (copied over on a flash
/// drive): a copy of the database with students and deposits only (login
/// accounts removed), plus when it was made.
class OfficerDataFile {
  static const extension = 'ecoearn';

  static Future<void> export(Database db, String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    await db.execute('VACUUM INTO ?', [path]);

    final copy = await databaseFactoryFfi.openDatabase(path);
    try {
      await copy.execute('DROP TABLE accounts');
      await copy.execute('CREATE TABLE export_info (exported_at TEXT NOT NULL)');
      await copy.insert('export_info', {'exported_at': DateTime.now().toIso8601String()});
      await copy.execute('VACUUM'); // so the deleted accounts aren't left in free pages
    } finally {
      await copy.close();
    }
  }

  /// Returns when the file was exported (the latest export it contains), or
  /// null if it isn't an EcoEarn data file.
  static Future<DateTime?> exportedAt(String path) async {
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
      return await _latestExport(db);
    } catch (_) {
      return null;
    } finally {
      await db?.close();
    }
  }

  static Future<DateTime?> _latestExport(DatabaseExecutor db, {String schema = 'main'}) async {
    final tables = await db.rawQuery(
        "SELECT name FROM $schema.sqlite_master WHERE name IN ('students', 'deposits', 'export_info')");
    if (tables.length != 3) return null;
    final rows = await db.rawQuery('SELECT MAX(exported_at) AS t FROM $schema.export_info');
    final latest = rows.first['t'] as String?;
    return latest == null ? null : DateTime.parse(latest);
  }

  /// Files from before records had permanent IDs (app before schema v3) can't be merged.
  static Future<bool> _hasSyncIds(DatabaseExecutor db, {String schema = 'main'}) async {
    final columns = await db.rawQuery('PRAGMA $schema.table_info(deposits)');
    return columns.any((c) => c['name'] == 'sync_id');
  }
}

/// What an import changed.
class ImportResult {
  const ImportResult.failed(this.error)
      : studentsAdded = 0,
        studentsUpdated = 0,
        depositsAdded = 0,
        depositsAlreadyThere = 0;

  const ImportResult({
    required this.studentsAdded,
    required this.studentsUpdated,
    required this.depositsAdded,
    required this.depositsAlreadyThere,
  }) : error = null;

  final String? error;
  final int studentsAdded;
  final int studentsUpdated;
  final int depositsAdded;
  final int depositsAlreadyThere;

  String get summary {
    if (error != null) return error!;
    String count(int n, String what) => '$n $what${n == 1 ? '' : 's'}';
    final parts = [
      'added ${count(depositsAdded, 'deposit')}',
      if (studentsAdded > 0) count(studentsAdded, 'new student'),
      if (studentsUpdated > 0) '${count(studentsUpdated, 'student')} updated',
    ];
    final already = depositsAlreadyThere > 0 ? ' ${count(depositsAlreadyThere, 'deposit')} were already here.' : '';
    return 'Imported: ${parts.join(', ')}.$already';
  }
}

/// The officer's own copy of the data. Each imported file is merged into it:
/// new students and deposits are added, changed students are updated, and
/// nothing is ever deleted. Records are matched by their permanent sync IDs,
/// so importing the same file twice, or files from two laptops, never
/// duplicates anything. Kept apart from the machine's database.
class OfficerData extends ChangeNotifier {
  OfficerData(this._folder);

  final String _folder;

  String get _path => p.join(_folder, 'officer_data.${OfficerDataFile.extension}');

  Database? _db;
  DateTime? _exportedAt;
  StudentRepository? _students;
  Reports? _reports;
  int _revision = 0;

  bool get hasData => _db != null;

  /// When the newest data imported so far was exported.
  DateTime? get exportedAt => _exportedAt;
  StudentRepository? get students => _students;
  Reports? get reports => _reports;

  /// Changes after every import, so screens can reload.
  int get revision => _revision;

  /// Opens the officer's data, if anything was imported before.
  Future<void> open() async {
    if (_db != null || !await File(_path).exists()) return;
    final exportedAt = await OfficerDataFile.exportedAt(_path);
    if (exportedAt == null) return;

    final db = await databaseFactoryFfi.openDatabase(_path, options: OpenDatabaseOptions(readOnly: true));
    final students = StudentRepository(db);
    await students.load();
    _db = db;
    _exportedAt = exportedAt;
    _students = students;
    _reports = Reports(db);
    _revision++;
    notifyListeners();
  }

  /// Merges the data file at [sourcePath] into the officer's data.
  Future<ImportResult> import(String sourcePath) async {
    if (await OfficerDataFile.exportedAt(sourcePath) == null) {
      return const ImportResult.failed(
          'That file is not an EcoEarn data file. Ask the admin to export one (Reports → Export).');
    }
    await _close();
    await Directory(_folder).create(recursive: true);

    final ImportResult result;
    try {
      result = await File(_path).exists() ? await _merge(sourcePath) : await _adopt(sourcePath);
    } catch (e) {
      await open();
      return ImportResult.failed('Could not import the file: $e');
    }
    await open();
    return result;
  }

  /// First import: the file becomes the officer's data.
  Future<ImportResult> _adopt(String sourcePath) async {
    await File(sourcePath).copy(_path);
    final db = await databaseFactoryFfi.openDatabase(_path);
    try {
      final students = await db.rawQuery('SELECT COUNT(*) AS n FROM students');
      final deposits = await db.rawQuery('SELECT COUNT(*) AS n FROM deposits');
      return ImportResult(
        studentsAdded: students.first['n'] as int,
        studentsUpdated: 0,
        depositsAdded: deposits.first['n'] as int,
        depositsAlreadyThere: 0,
      );
    } finally {
      await db.close();
    }
  }

  Future<ImportResult> _merge(String sourcePath) async {
    final db = await databaseFactoryFfi.openDatabase(_path);
    try {
      await db.execute('ATTACH DATABASE ? AS src', [sourcePath]);
      try {
        final localIds = await OfficerDataFile._hasSyncIds(db);
        final sourceIds = await OfficerDataFile._hasSyncIds(db, schema: 'src');
        if (!sourceIds) {
          return const ImportResult.failed(
              'That file was exported by an older version of EcoEarn. Ask the admin to export a new one.');
        }
        if (!localIds) {
          // The officer's data predates permanent IDs and can't be merged: start over from the new file.
          await db.execute('DETACH DATABASE src');
          await db.close();
          await File(_path).delete();
          return _adopt(sourcePath);
        }
        return await db.transaction((txn) => _mergeInto(txn));
      } finally {
        if (db.isOpen) await db.execute('DETACH DATABASE src');
      }
    } finally {
      if (db.isOpen) await db.close();
    }
  }

  Future<ImportResult> _mergeInto(Transaction txn) async {
    final localLatest = await OfficerDataFile._latestExport(txn);
    final sourceExported = (await OfficerDataFile._latestExport(txn, schema: 'src'))!;
    // Student details (name, card, section) only follow a file that is newer
    // than everything imported before, so an old file can't undo newer changes.
    final newer = localLatest == null || !sourceExported.isBefore(localLatest);

    var studentsAdded = 0;
    var studentsUpdated = 0;
    final localIdFor = <int, int>{}; // source student id -> officer student id

    for (final s in await txn.rawQuery('SELECT * FROM src.students')) {
      final syncId = s['sync_id'] as String;
      final studentNo = s['student_no'] as String;
      final card = s['rfid_uid'] as String?;
      final fields = {
        'student_no': studentNo,
        'name': s['name'],
        'grade_section': s['grade_section'],
        'rfid_uid': card,
      };

      var match = await txn.query('students', where: 'sync_id = ?', whereArgs: [syncId]);
      // The same student registered on another laptop has another sync_id but the same ID number.
      if (match.isEmpty) match = await txn.query('students', where: 'student_no = ?', whereArgs: [studentNo]);

      if (match.isNotEmpty) {
        final local = match.first;
        final id = local['id'] as int;
        localIdFor[s['id'] as int] = id;
        final changed = fields.entries.any((f) => local[f.key] != f.value);
        if (newer && changed) {
          // A card moves to whoever the newest file says has it.
          if (card != null) {
            await txn.update('students', {'rfid_uid': null}, where: 'rfid_uid = ? AND id != ?', whereArgs: [card, id]);
          }
          final takenNo = await txn.query('students', where: 'student_no = ? AND id != ?', whereArgs: [studentNo, id]);
          await txn.update('students', {...fields, if (takenNo.isNotEmpty) 'student_no': local['student_no']},
              where: 'id = ?', whereArgs: [id]);
          studentsUpdated++;
        }
      } else {
        if (card != null) {
          final holder = await txn.query('students', where: 'rfid_uid = ?', whereArgs: [card]);
          if (holder.isNotEmpty) {
            if (newer) {
              await txn.update('students', {'rfid_uid': null}, where: 'rfid_uid = ?', whereArgs: [card]);
            } else {
              fields['rfid_uid'] = null;
            }
          }
        }
        localIdFor[s['id'] as int] = await txn.insert('students', {
          ...fields,
          'created_at': s['created_at'],
          'sync_id': syncId,
        });
        studentsAdded++;
      }
    }

    var depositsAdded = 0;
    var depositsAlreadyThere = 0;
    final known = {for (final r in await txn.query('deposits', columns: ['sync_id', 'student_id'])) r['sync_id']: r};
    for (final d in await txn.rawQuery('SELECT * FROM src.deposits')) {
      final sourceStudent = d['student_id'] as int?;
      final studentId = sourceStudent == null ? null : localIdFor[sourceStudent];
      final existing = known[d['sync_id']];
      if (existing != null) {
        depositsAlreadyThere++;
        // Credited since: the card was assigned to a student after the earlier export.
        if (existing['student_id'] == null && studentId != null) {
          await txn.update('deposits', {'student_id': studentId}, where: 'sync_id = ?', whereArgs: [d['sync_id']]);
        }
        continue;
      }
      await txn.insert('deposits', {
        'occurred_at': d['occurred_at'],
        'rfid_uid': d['rfid_uid'],
        'student_id': studentId,
        'grams': d['grams'],
        'points': d['points'],
        'reject_reason': d['reject_reason'],
        'source': d['source'],
        'sync_id': d['sync_id'],
        'grams_per_point': d['grams_per_point'],
      });
      depositsAdded++;
    }

    await txn.execute('''
      INSERT INTO point_rate_changes (changed_at, grams_per_point, changed_by)
      SELECT changed_at, grams_per_point, changed_by FROM src.point_rate_changes r
      WHERE NOT EXISTS (SELECT 1 FROM point_rate_changes l
                        WHERE l.changed_at = r.changed_at AND l.grams_per_point = r.grams_per_point)''');
    if (newer) await txn.execute('INSERT OR REPLACE INTO settings SELECT * FROM src.settings');
    await txn.insert('export_info', {'exported_at': sourceExported.toIso8601String()});

    return ImportResult(
      studentsAdded: studentsAdded,
      studentsUpdated: studentsUpdated,
      depositsAdded: depositsAdded,
      depositsAlreadyThere: depositsAlreadyThere,
    );
  }

  Future<void> _close() async {
    _students?.dispose();
    await _db?.close();
    _db = null;
    _exportedAt = null;
    _students = null;
    _reports = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }
}
