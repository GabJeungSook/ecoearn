import 'dart:io';

import 'package:ecoearn_app/auth/account.dart';
import 'package:ecoearn_app/auth/auth_service.dart';
import 'package:ecoearn_app/auth/password_hash.dart';
import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/officer_data.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    await db.insert('deposits', {
      'occurred_at': '2026-10-27T10:00:00.000',
      'rfid_uid': 'A3F29B11',
      'student_id': students.byUid('A3F29B11')!.id,
      'grams': 39.0,
      'points': 3,
    });

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
    expect(await officer.import(file), isNull);
    expect(officer.hasData, isTrue);
    expect(officer.students!.byUid('A3F29B11')!.points, 3);
    expect((await officer.reports!.monthly(2026, 10)).points, 3);

    // Re-importing replaces the copy; a non-EcoEarn file is refused.
    expect(await officer.import(file), isNull);
    final junk = File(p.join(folder.path, 'junk.ecoearn'))..writeAsStringSync('not a database');
    expect(await officer.import(junk.path), contains('not an EcoEarn data file'));
    expect(officer.hasData, isTrue);
    officer.dispose();
  });
}
