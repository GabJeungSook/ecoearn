import 'dart:io';

import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/fees.dart';
import 'package:ecoearn_app/data/officer_data.dart';
import 'package:ecoearn_app/data/payments.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:ecoearn_app/data/sync_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> addDeposit(Database db, int studentId, int points) => db.insert('deposits', {
      'occurred_at': DateTime.now().toIso8601String(),
      'rfid_uid': 'A3F29B11',
      'student_id': studentId,
      'grams': points * 10.0,
      'points': points,
      'sync_id': newSyncId(),
      'grams_per_point': 10,
    });

void main() {
  late Database db;
  late StudentRepository students;
  late FeeBook fees;
  late PaymentBook payments;

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    students = StudentRepository(db);
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    fees = FeeBook(db);
    await fees.load();
    payments = PaymentBook(db, students);
    await payments.load();
  });

  tearDown(() => db.close());

  Student juan() => students.students.single;

  test('fees: validated, priced in points (rounded up), archived instead of deleted', () async {
    expect(fees.pesosPerPoint, 1);
    expect(await fees.addFee('', 20), isNotNull);
    expect(await fees.addFee('Late fee', 0), isNotNull);
    expect(await fees.addFee('Late fee', 20), isNull);
    expect(await fees.addFee('late fee', 30), contains('already'));
    expect(fees.pointsFor(20), 20);
    await fees.setPesosPerPoint(1.5, changedBy: 'Gab');
    expect(fees.pointsFor(20), 14); // 13.33 -> 14: paid exactly, never short
    expect(fees.history.single.changedBy, 'Gab');
    await fees.setActive(fees.fees.single, false);
    expect(fees.activeFees, isEmpty);
    expect(fees.fees, hasLength(1));
  });

  test('a fee is paid only in full, from the balance, and a void gives the points back', () async {
    await fees.addFee('Late fee', 20);
    final lateFee = fees.activeFees.single;
    await addDeposit(db, juan().id!, 15);
    await students.load();

    final short = await payments.pay(student: juan(), fee: lateFee, book: fees, processedBy: 'Officer Ana');
    expect(short, contains('needs 20'));
    expect(payments.payments, isEmpty);

    await addDeposit(db, juan().id!, 10);
    await students.load();
    expect(await payments.pay(student: juan(), fee: lateFee, book: fees, processedBy: 'Officer Ana'), isNull);
    expect((juan().earned, juan().spent, juan().points), (25, 20, 5));
    expect(payments.payments.single.processedBy, 'Officer Ana');

    // A second one doesn't fit any more.
    expect(await payments.pay(student: juan(), fee: lateFee, book: fees, processedBy: 'Officer Ana'), isNotNull);

    expect(await payments.voidPayment(payments.payments.single, reason: '', voidedBy: 'Ana'), isNotNull);
    expect(await payments.voidPayment(payments.payments.single, reason: 'Wrong fee', voidedBy: 'Ana'), isNull);
    expect(juan().points, 25);
    expect(payments.payments.single.voided, isTrue); // kept in the record
  });

  test('officer imports keep payments, merge fees and the peso rate by newest change', () async {
    final folder = await Directory.systemTemp.createTemp('ecoearn_pay');
    addTearDown(() => folder.delete(recursive: true));
    await addDeposit(db, juan().id!, 30);
    await fees.addFee('Late fee', 20);
    final first = p.join(folder.path, 'first.ecoearn');
    await OfficerDataFile.export(db, first);

    final officer = OfficerData(p.join(folder.path, 'officer'));
    addTearDown(officer.dispose);
    await officer.import(first);
    final officerFees = officer.fees!;
    final student = officer.students!.students.single;
    expect(await officer.payments!.pay(
        student: student, fee: officerFees.activeFees.single, book: officerFees, processedBy: 'Ana'), isNull);
    expect(officer.students!.students.single.points, 10);

    // The officer adds a fee and changes the rate; later the admin changes the late fee and adds deposits.
    await officerFees.addFee('Penalty', 50);
    await officerFees.setPesosPerPoint(2, changedBy: 'Ana');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await fees.updateFee(fees.activeFees.single, 'Late fee', 25);
    await addDeposit(db, juan().id!, 5);
    final second = p.join(folder.path, 'second.ecoearn');
    await OfficerDataFile.export(db, second);

    await officer.import(second);
    final s = officer.students!.students.single;
    expect((s.earned, s.spent, s.points), (35, 20, 15)); // payment kept, new deposit added
    expect(officer.payments!.payments, hasLength(1));
    expect(officer.fees!.fees.map((f) => (f.name, f.amount)), containsAll([('Late fee', 25.0), ('Penalty', 50.0)]));
    expect(officer.fees!.pesosPerPoint, 2); // the officer's change is newer than the admin's (never changed)
  });
}
