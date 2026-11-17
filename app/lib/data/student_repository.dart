import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'student.dart';
import 'sync_id.dart';

/// All students with their point balances, kept in memory (a school's worth
/// of students is small) and reloaded after every change.
class StudentRepository extends ChangeNotifier {
  StudentRepository(this._db);

  final Database _db;
  List<Student> _students = const [];
  Map<String, Student> _byUid = const {};

  /// Sorted by name.
  List<Student> get students => _students;

  Student? byUid(String uid) => _byUid[uid];

  Future<void> load() async {
    final rows = await _db.rawQuery('''
      SELECT s.*,
        COALESCE((SELECT SUM(d.points) FROM deposits d WHERE d.student_id = s.id), 0) AS earned,
        COALESCE((SELECT SUM(p.points) FROM payments p WHERE p.student_id = s.id AND p.voided_at IS NULL), 0) AS spent
      FROM students s
      ORDER BY s.name COLLATE NOCASE''');
    _students = rows.map(Student.fromRow).toList();
    _byUid = {
      for (final s in _students)
        if (s.rfidUid != null) s.rfidUid!: s,
    };
    notifyListeners();
  }

  /// Adds a new student or updates an existing one.
  /// Returns a message to show the user if it can't be saved, or null on success.
  ///
  /// Bottles deposited with a card before it was assigned to anyone are
  /// credited to the student who receives that card.
  Future<String?> save(Student student) async {
    final studentNo = student.studentNo.trim();
    final name = student.name.trim();
    final uid = Student.normalizeUid(student.rfidUid);

    if (studentNo.isEmpty) return 'Student ID number is required.';
    if (name.isEmpty) return 'Name is required.';
    for (final other in _students) {
      if (other.id == student.id) continue;
      if (other.studentNo == studentNo) return 'Student ID $studentNo already belongs to ${other.name}.';
      if (uid != null && other.rfidUid == uid) return 'Card $uid is already assigned to ${other.name}.';
    }

    final row = {
      'student_no': studentNo,
      'name': name,
      'grade_section': student.gradeSection.trim(),
      'rfid_uid': uid,
    };
    await _db.transaction((txn) async {
      final int id;
      if (student.id == null) {
        id = await txn.insert('students', {
          ...row,
          'created_at': DateTime.now().toIso8601String(),
          'sync_id': newSyncId(),
        });
      } else {
        id = student.id!;
        await txn.update('students', row, where: 'id = ?', whereArgs: [id]);
      }
      if (uid != null) {
        await txn.update('deposits', {'student_id': id},
            where: 'rfid_uid = ? AND student_id IS NULL', whereArgs: [uid]);
      }
    });
    await load();
    return null;
  }

  /// Returns a message to show the user if the student can't be deleted, or null on success.
  Future<String?> delete(Student student) async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM deposits WHERE student_id = ?', [student.id]);
    if (rows.first['n'] != 0) {
      return '${student.name} has deposit history, so they can\'t be deleted. '
          'To stop them earning points, edit them and remove their card.';
    }
    await _db.delete('students', where: 'id = ?', whereArgs: [student.id]);
    await load();
    return null;
  }
}
