import 'dart:async';

import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/deposit_recorder.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:ecoearn_app/serial/device_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late StudentRepository students;
  late StreamController<DeviceEvent> events;
  late DepositRecorder recorder;

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    students = StudentRepository(db);
    await students.load();
    events = StreamController<DeviceEvent>();
    recorder = DepositRecorder(db: db, students: students, events: events.stream);
  });

  tearDown(() async {
    recorder.dispose();
    await events.close();
    await db.close();
  });

  Future<void> deliver(List<DeviceEvent> list) async {
    list.forEach(events.add);
    await pumpEventQueue();
    await recorder.flush();
  }

  Future<List<Map<String, Object?>>> deposits() => db.query('deposits', orderBy: 'id');

  test('demo (simulated) deposits are never saved', () async {
    await deliver([
      WeightEvent(uid: 'A3F29B11', grams: 30, points: 3, simulated: true),
      RejectEvent(uid: 'A3F29B11', reason: 'too_heavy', grams: 120, simulated: true),
      WeightEvent(uid: 'A3F29B11', grams: 20, points: 2),
    ]);
    expect((await deposits()).map((d) => d['points']), [2]);
  });

  test('saves a student and normalizes the card UID', () async {
    expect(await students.save(const Student(studentNo: '2024-001', name: ' Juan Dela Cruz ', rfidUid: 'a3 f2 9b 11')),
        isNull);
    final juan = students.students.single;
    expect(juan.name, 'Juan Dela Cruz');
    expect(juan.rfidUid, 'A3F29B11');
    expect(students.byUid('A3F29B11')?.name, 'Juan Dela Cruz');
  });

  test('rejects duplicate ID numbers and cards', () async {
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    expect(await students.save(const Student(studentNo: '2024-001', name: 'Maria')),
        contains('already belongs to Juan'));
    expect(await students.save(const Student(studentNo: '2024-002', name: 'Maria', rfidUid: 'A3F29B11')),
        contains('already assigned to Juan'));
    expect(await students.save(const Student(studentNo: '', name: 'Maria')), isNotNull);
  });

  test('records deposits and adds up the point balance', () async {
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    await deliver([
      CardEvent(uid: 'A3F29B11'),
      WeightEvent(uid: 'A3F29B11', grams: 39, points: 3),
      WeightEvent(uid: 'A3F29B11', grams: 21.5, points: 2),
      RejectEvent(uid: 'A3F29B11', reason: 'too_heavy', grams: 120),
      BinEvent(level: 40),
    ]);

    final rows = await deposits();
    expect(rows, hasLength(3)); // card and bin events aren't deposits
    expect(rows.last['reject_reason'], 'too_heavy');
    expect(rows.last['points'], 0);
    expect(students.byUid('A3F29B11')!.points, 5);
  });

  test('unregistered card deposits are credited when the card is assigned', () async {
    await deliver([WeightEvent(uid: '5C7E0D42', grams: 30, points: 3)]);
    expect((await deposits()).single['student_id'], isNull);

    await students.save(const Student(studentNo: '2024-002', name: 'Maria', rfidUid: '5C7E0D42'));
    expect(students.byUid('5C7E0D42')!.points, 3);
  });

  test('a student with deposit history cannot be deleted', () async {
    await students.save(const Student(studentNo: '2024-001', name: 'Juan', rfidUid: 'A3F29B11'));
    await students.save(const Student(studentNo: '2024-002', name: 'Maria'));
    await deliver([WeightEvent(uid: 'A3F29B11', grams: 30, points: 3)]);

    final juan = students.byUid('A3F29B11')!;
    expect(await students.delete(juan), contains('deposit history'));

    final maria = students.students.firstWhere((s) => s.name == 'Maria');
    expect(await students.delete(maria), isNull);
    expect(students.students.map((s) => s.name), ['Juan']);
  });
}
