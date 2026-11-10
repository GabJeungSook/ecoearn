import 'dart:async';

import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/deposit_recorder.dart';
import 'package:ecoearn_app/data/point_rules.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:ecoearn_app/serial/device_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PointRules rules;

  setUp(() async {
    db = await AppDatabase.open(inMemoryDatabasePath);
    rules = PointRules(db);
    await rules.load();
  });

  tearDown(() => db.close());

  test('starts at 1 point per 10 g; changes are validated and logged', () async {
    expect(rules.gramsPerPoint, 10);
    expect(rules.pointsFor(39), 3);
    expect(await rules.setGramsPerPoint(0, changedBy: 'Gab'), isNotNull);
    expect(await rules.setGramsPerPoint(15, changedBy: 'Gab'), isNull);
    expect(rules.pointsFor(39), 2);
    expect(rules.history.single.gramsPerPoint, 15);
    expect(rules.history.single.changedBy, 'Gab');

    final reloaded = PointRules(db);
    await reloaded.load();
    expect(reloaded.gramsPerPoint, 15);
  });

  test('each deposit keeps the rate and points it was earned with', () async {
    final students = StudentRepository(db);
    await students.load();
    final events = StreamController<DeviceEvent>();
    final recorder = DepositRecorder(db: db, students: students, events: events.stream, rules: rules);

    events.add(WeightEvent(uid: 'A3F29B11', grams: 39, points: 3, gramsPerPoint: 10));
    await pumpEventQueue();
    await rules.setGramsPerPoint(20, changedBy: 'Gab');
    events.add(WeightEvent(uid: 'A3F29B11', grams: 39, points: 1)); // older firmware: no rate in the event
    await pumpEventQueue();
    await recorder.flush();

    final rows = await db.query('deposits', orderBy: 'id');
    expect(rows.map((r) => (r['points'], r['grams_per_point'])), [(3, 10), (1, 20)]);
    expect(rows.every((r) => (r['sync_id'] as String).length == 32), isTrue);

    recorder.dispose();
    await events.close();
  });

  test('boot and weight events carry the machine rate', () {
    final boot = DeviceEvent.tryParse('{"event":"boot","version":"0.3.0","grams_per_point":12}');
    expect(boot, isA<BootEvent>().having((e) => e.gramsPerPoint, 'rate', 12));
    final weight = DeviceEvent.tryParse('{"event":"weight","uid":"X","grams":30,"points":2,"grams_per_point":12}');
    expect(weight, isA<WeightEvent>().having((e) => e.gramsPerPoint, 'rate', 12));
    expect(DeviceEvent.tryParse('{"event":"boot","version":"0.2.8"}'),
        isA<BootEvent>().having((e) => e.gramsPerPoint, 'rate', null));
  });
}
