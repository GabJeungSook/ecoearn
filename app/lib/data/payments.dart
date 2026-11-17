import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fees.dart';
import 'student.dart';
import 'student_repository.dart';
import 'sync_id.dart';

class Payment {
  const Payment(this.row);

  final Map<String, Object?> row;

  int get id => row['id'] as int;
  int get studentId => row['student_id'] as int;
  String get studentName => (row['name'] as String?) ?? 'Unknown student';
  String get studentNo => (row['student_no'] as String?) ?? '';
  String get gradeSection => (row['grade_section'] as String?) ?? '';
  String get feeName => row['fee_name'] as String;
  double get amount => (row['amount'] as num).toDouble();
  int get points => row['points'] as int;
  double get pesosPerPoint => (row['pesos_per_point'] as num).toDouble();
  DateTime get paidAt => DateTime.parse(row['paid_at'] as String);
  String get processedBy => row['processed_by'] as String;
  bool get voided => row['voided_at'] != null;
  DateTime? get voidedAt => voided ? DateTime.parse(row['voided_at'] as String) : null;
  String? get voidReason => row['void_reason'] as String?;
  String? get voidedBy => row['voided_by'] as String?;
}

/// Fees paid with points, on the officer's computer. A fee is paid in full and
/// exactly: the student needs at least the fee's points, never part of it.
/// Points only leave here, and only arrive (deposits) through imports, so an
/// out-of-date import can only show a balance that is too low, never too high.
class PaymentBook extends ChangeNotifier {
  PaymentBook(this._db, this._students);

  final Database _db;
  final StudentRepository _students;
  List<Payment> _payments = const [];

  /// Newest first.
  List<Payment> get payments => _payments;

  Future<void> load() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, s.name, s.student_no, s.grade_section
      FROM payments p LEFT JOIN students s ON s.id = p.student_id
      ORDER BY p.paid_at DESC, p.id DESC''');
    _payments = rows.map(Payment.new).toList();
    notifyListeners();
  }

  List<Payment> forStudent(int studentId) => _payments.where((p) => p.studentId == studentId).toList();

  /// Pays [fee] for [student] with points. Returns a message to show if it
  /// can't be paid, or null on success.
  Future<String?> pay({required Student student, required Fee fee, required FeeBook book, required String processedBy}) async {
    if (!fee.active) return '${fee.name} can no longer be paid with points.';
    final needed = book.pointsFor(fee.amount);
    String? error;
    await _db.transaction((txn) async {
      // Check the balance inside the transaction, from the database itself.
      final row = (await txn.rawQuery('''
        SELECT
          COALESCE((SELECT SUM(points) FROM deposits WHERE student_id = ?), 0) -
          COALESCE((SELECT SUM(points) FROM payments WHERE student_id = ? AND voided_at IS NULL), 0) AS balance''',
          [student.id, student.id])).first;
      final balance = row['balance'] as int;
      if (balance < needed) {
        error = '${student.name} has $balance ${balance == 1 ? 'point' : 'points'}; '
            '${fee.name} needs $needed. Fees can only be paid in full.';
        return;
      }
      await txn.insert('payments', {
        'sync_id': newSyncId(),
        'student_id': student.id,
        'fee_name': fee.name,
        'amount': fee.amount,
        'points': needed,
        'pesos_per_point': book.pesosPerPoint,
        'paid_at': DateTime.now().toIso8601String(),
        'processed_by': processedBy,
      });
    });
    if (error != null) return error;
    await _students.load();
    await load();
    return null;
  }

  /// Cancels a payment made by mistake: its points go back to the student.
  /// It stays in the record, marked voided, with the reason.
  Future<String?> voidPayment(Payment payment, {required String reason, required String voidedBy}) async {
    if (payment.voided) return 'This payment is already voided.';
    if (reason.trim().isEmpty) return 'Enter why the payment is voided.';
    await _db.update(
      'payments',
      {'voided_at': DateTime.now().toIso8601String(), 'void_reason': reason.trim(), 'voided_by': voidedBy},
      where: 'id = ? AND voided_at IS NULL',
      whereArgs: [payment.id],
    );
    await _students.load();
    await load();
    return null;
  }
}
