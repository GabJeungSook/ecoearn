import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/csv_export.dart';
import 'package:ecoearn_app/data/reports.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late Reports reports;
  late int juanId;

  Future<void> deposit(String at, String uid, double grams, int points, {int? studentId, String? reject}) =>
      db.insert('deposits', {
        'occurred_at': at,
        'rfid_uid': uid,
        'student_id': studentId,
        'grams': grams,
        'points': points,
        'reject_reason': reject,
      });

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    reports = Reports(db);
    final students = StudentRepository(db);
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', gradeSection: '12 - STEM A', rfidUid: 'A3F29B11'));
    juanId = students.byUid('A3F29B11')!.id!;

    await deposit('2026-09-30T23:59:59.000', 'A3F29B11', 20, 2, studentId: juanId); // previous month
    await deposit('2026-10-01T00:00:00.000', 'A3F29B11', 39, 3, studentId: juanId);
    await deposit('2026-10-15T10:00:00.000', 'A3F29B11', 25.5, 2, studentId: juanId);
    await deposit('2026-10-15T10:01:00.000', 'A3F29B11', 120, 0, studentId: juanId, reject: 'too_heavy');
    await deposit('2026-10-31T23:59:59.000', '5C7E0D42', 30, 3); // unregistered card
    await deposit('2026-11-01T00:00:00.000', 'A3F29B11', 40, 4, studentId: juanId); // next month
  });

  tearDown(() => db.close());

  test('monthly report totals only that month, per student and per unregistered card', () async {
    final report = await reports.monthly(2026, 10);
    expect(report.title, 'October 2026');
    expect(report.rows, hasLength(2));

    final juan = report.rows.first;
    expect(juan.name, 'Juan');
    expect(juan.bottles, 2); // the rejected item isn't a collected bottle
    expect(juan.grams, 64.5);
    expect(juan.points, 5);
    expect(juan.rejected, 1);

    final unregistered = report.rows.last;
    expect(unregistered.isRegistered, isFalse);
    expect(unregistered.name, 'Unregistered card 5C7E0D42');

    expect(report.bottles, 3);
    expect(report.points, 8);
    expect(report.students, 1);
  });

  test('December rolls over into the next year', () async {
    await deposit('2026-12-31T12:00:00.000', 'A3F29B11', 10, 1, studentId: juanId);
    await deposit('2027-01-01T00:00:00.000', 'A3F29B11', 10, 1, studentId: juanId);
    expect((await reports.monthly(2026, 12)).bottles, 1);
  });

  test('deposit export includes student details', () async {
    expect(await reports.deposits(), hasLength(6));
    final october = await reports.deposits(year: 2026, month: 10);
    expect(october, hasLength(4));

    final csv = depositsCsv(october);
    expect(csv.first.first, 'Deposit ID');
    expect(csv[1].sublist(1),
        ['2026-10-01', '00:00:00', 'A3F29B11', '2024-001', 'Juan', '12 - STEM A', '39.0', 3, '', 'accepted', '', 'live']);
    expect(csv[3][10], 'rejected');
    expect(csv[4][5], 'Unregistered');
  });

  test("one student's record, and the months that have deposits", () async {
    final juan = (await db.query('students', where: "name = 'Juan'")).single['id'] as int;
    final all = await reports.deposits(studentId: juan);
    expect(all, isNotEmpty);
    expect(all.every((d) => d.studentId == juan), isTrue);
    final months = await reports.monthsWithDeposits();
    expect(months.first, isA<(int, int)>());
    expect(months, contains((2026, 10)));
    final juanOctober = await reports.deposits(studentId: juan, year: 2026, month: 10);
    expect(juanOctober.length, lessThanOrEqualTo(all.length));
  });

  test('CSV quotes fields with commas and quotes', () {
    expect(toCsv([
      ['Dela Cruz, Juan', 'say "hi"', 3],
      ['plain', null, 1.5],
    ]), '"Dela Cruz, Juan","say ""hi""",3\r\nplain,,1.5');
  });
}
