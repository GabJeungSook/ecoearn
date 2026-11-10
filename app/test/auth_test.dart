import 'dart:io';
import 'dart:isolate';

import 'package:ecoearn_app/auth/account.dart';
import 'package:ecoearn_app/auth/auth_service.dart';
import 'package:ecoearn_app/auth/password_hash.dart';
import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/officer_data.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:ecoearn_app/data/sync_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> addDeposit(Database db, int studentId, String card, {required int points}) => db.insert('deposits', {
      'occurred_at': '2026-10-27T10:00:00.000',
      'rfid_uid': card,
      'student_id': studentId,
      'grams': points * 10.0 + 4,
      'points': points,
      'sync_id': newSyncId(),
      'grams_per_point': 10,
    });

void main() {
  late Database db;
  late AuthService auth;

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    auth = AuthService(db);
    await auth.load();
  });

  tearDown(() => db.close());

  test('password hashes verify only the right password and are salted', () {
    final a = hashPassword('secret123');
    final b = hashPassword('secret123');
    expect(a, isNot(b));
    expect(verifyPassword('secret123', a), isTrue);
    expect(verifyPassword('secret124', a), isFalse);
    expect(verifyPassword('secret123', 'garbage'), isFalse);
  });

  test('first admin, sign in, sign out', () async {
    expect(auth.hasAccounts, isFalse);
    expect(await auth.save(username: 'Admin', displayName: 'Gab', role: Role.admin, password: 'secret123'), isNull);
    expect(auth.accounts.single.username, 'admin'); // stored lowercase

    expect(await auth.login('admin', 'wrong-pass'), isNotNull);
    expect(auth.current, isNull);
    expect(await auth.login(' ADMIN ', 'secret123'), isNull);
    expect(auth.current?.role, Role.admin);

    auth.logout();
    expect(auth.current, isNull);
  });

  test('works while a screen is listening (listeners hold unsendable objects)', () async {
    // In the app, widgets listen to AuthService. A ReceivePort stands in for
    // the things those listeners reference that can't be sent to an isolate.
    final port = ReceivePort();
    addTearDown(port.close);
    auth.addListener(() => port.sendPort);

    expect(await auth.save(username: 'admin', displayName: 'Gab', role: Role.admin, password: 'secret123'), isNull);
    expect(await auth.login('admin', 'secret123'), isNull);
    expect(await auth.isAdminPassword('secret123'), isTrue);
  });

  test('validation and last-admin protection', () async {
    expect(await auth.save(username: 'ab', displayName: 'X', role: Role.admin, password: 'secret123'), contains('3 characters'));
    expect(await auth.save(username: 'admin', displayName: 'X', role: Role.admin, password: '123'), contains('6 characters'));

    await auth.save(username: 'admin', displayName: 'Gab', role: Role.admin, password: 'secret123');
    await auth.save(username: 'kiosk', displayName: 'Display', role: Role.display, password: 'display1');
    expect(await auth.save(username: 'kiosk', displayName: 'Again', role: Role.officer, password: 'secret123'),
        contains('already taken'));

    final admin = auth.accounts.firstWhere((a) => a.role == Role.admin);
    expect(await auth.save(existing: admin, username: 'admin', displayName: 'Gab', role: Role.officer, password: ''),
        contains('only admin'));
    expect(await auth.delete(admin), contains('last admin'));

    // Editing without a new password keeps the old one.
    final kiosk = auth.accounts.firstWhere((a) => a.role == Role.display);
    await auth.save(existing: kiosk, username: 'kiosk', displayName: 'Lobby screen', role: Role.display, password: '');
    expect(await auth.login('kiosk', 'display1'), isNull);
    expect(auth.current?.displayName, 'Lobby screen');

    expect(await auth.isAdminPassword('secret123'), isTrue);
    expect(await auth.isAdminPassword('display1'), isFalse);
  });

  test('officer data file has students and deposits but no accounts', () async {
    await auth.save(username: 'admin', displayName: 'Gab', role: Role.admin, password: 'secret123');
    final students = StudentRepository(db);
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    await addDeposit(db, students.byUid('A3F29B11')!.id!, 'A3F29B11', points: 3);

    final folder = await Directory.systemTemp.createTemp('ecoearn_test');
    addTearDown(() => folder.delete(recursive: true));
    final file = p.join(folder.path, 'export.ecoearn');
    await OfficerDataFile.export(db, file);

    final copy = await databaseFactoryFfi.openDatabase(file);
    final tables = (await copy.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")).map((r) => r['name']);
    await copy.close();
    expect(tables, containsAll(['students', 'deposits', 'export_info']));
    expect(tables, isNot(contains('accounts')));

    final officer = OfficerData(p.join(folder.path, 'officer'));
    final first = await officer.import(file);
    expect(first.error, isNull);
    expect((first.studentsAdded, first.depositsAdded), (1, 1));
    expect(officer.students!.byUid('A3F29B11')!.points, 3);
    expect((await officer.reports!.monthly(2026, 10)).points, 3);

    // A non-EcoEarn file is refused and the data stays.
    final junk = File(p.join(folder.path, 'junk.ecoearn'))..writeAsStringSync('not a database');
    expect((await officer.import(junk.path)).error, contains('not an EcoEarn data file'));
    expect(officer.hasData, isTrue);
    officer.dispose();
  });

  test('officer imports merge: new records added, nothing duplicated or lost', () async {
    final folder = await Directory.systemTemp.createTemp('ecoearn_merge');
    addTearDown(() => folder.delete(recursive: true));
    final students = StudentRepository(db);
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    final juanId = students.byUid('A3F29B11')!.id!;
    await addDeposit(db, juanId, 'A3F29B11', points: 3);
    final first = p.join(folder.path, 'first.ecoearn');
    await OfficerDataFile.export(db, first);

    final officer = OfficerData(p.join(folder.path, 'officer'));
    addTearDown(officer.dispose);
    await officer.import(first);

    // The same file again adds nothing.
    final again = await officer.import(first);
    expect((again.depositsAdded, again.depositsAlreadyThere, again.studentsAdded), (0, 1, 0));

    // Later on the machine: another deposit, a new student, Juan renamed.
    await addDeposit(db, juanId, 'A3F29B11', points: 2);
    await students.save(const Student(studentNo: '2024-002', name: 'Maria', rfidUid: '79EEB9A2'));
    await addDeposit(db, students.byUid('79EEB9A2')!.id!, '79EEB9A2', points: 5);
    await students.save(Student(id: juanId, studentNo: '2024-001', name: 'Juan Dela Cruz', rfidUid: 'A3F29B11'));
    await Future<void>.delayed(const Duration(milliseconds: 5)); // a later export time
    final second = p.join(folder.path, 'second.ecoearn');
    await OfficerDataFile.export(db, second);

    final merged = await officer.import(second);
    expect((merged.depositsAdded, merged.depositsAlreadyThere), (2, 1));
    expect((merged.studentsAdded, merged.studentsUpdated), (1, 1));
    expect(officer.students!.byUid('A3F29B11')!.points, 5);
    expect(officer.students!.byUid('A3F29B11')!.name, 'Juan Dela Cruz');
    expect(officer.students!.byUid('79EEB9A2')!.points, 5);

    // An older file doesn't undo the rename.
    await officer.import(first);
    expect(officer.students!.byUid('A3F29B11')!.name, 'Juan Dela Cruz');

    // A second laptop registered the same student (same ID number) on its own.
    final other = await AppDatabase.open(p.join(folder.path, 'laptop2.db')); // in-memory DBs are shared
    final otherStudents = StudentRepository(other);
    await otherStudents.save(const Student(studentNo: '2024-001', name: 'Juan Dela Cruz', rfidUid: 'A3F29B11'));
    await addDeposit(other, otherStudents.byUid('A3F29B11')!.id!, 'A3F29B11', points: 4);
    final third = p.join(folder.path, 'third.ecoearn');
    await OfficerDataFile.export(other, third);
    await other.close();

    final fromOther = await officer.import(third);
    expect((fromOther.depositsAdded, fromOther.studentsAdded), (1, 0));
    expect(officer.students!.students, hasLength(2));
    expect(officer.students!.byUid('A3F29B11')!.points, 9);
  });
}
