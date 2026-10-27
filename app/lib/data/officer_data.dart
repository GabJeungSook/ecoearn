import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'reports.dart';
import 'student_repository.dart';

/// The data file the admin exports for officers: a copy of the database with
/// students and deposits only (login accounts removed), plus when it was made.
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

  /// Returns when the file was exported, or null if it isn't an EcoEarn data file.
  static Future<DateTime?> exportedAt(String path) async {
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
      final rows = await db.query('export_info');
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE name IN ('students', 'deposits')");
      if (rows.isEmpty || tables.length != 2) return null;
      return DateTime.parse(rows.first['exported_at'] as String);
    } catch (_) {
      return null;
    } finally {
      await db?.close();
    }
  }
}

/// The officer's imported copy of the data. Kept in its own file, separate
/// from the machine's database, so importing can never overwrite live records.
class OfficerData extends ChangeNotifier {
  OfficerData(this._folder);

  final String _folder;

  String get _path => p.join(_folder, 'officer_data.${OfficerDataFile.extension}');

  Database? _db;
  DateTime? _exportedAt;
  StudentRepository? _students;
  Reports? _reports;

  bool get hasData => _db != null;
  DateTime? get exportedAt => _exportedAt;
  StudentRepository? get students => _students;
  Reports? get reports => _reports;

  /// Opens the last imported file, if there is one.
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
    notifyListeners();
  }

  /// Replaces the imported copy with [sourcePath]. Returns an error message, or null on success.
  Future<String?> import(String sourcePath) async {
    if (await OfficerDataFile.exportedAt(sourcePath) == null) {
      return 'That file is not an EcoEarn data file. Ask the admin to export one from the Reports screen.';
    }
    await _close();
    await Directory(_folder).create(recursive: true);
    await File(sourcePath).copy(_path);
    await open();
    return null;
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
