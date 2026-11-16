import 'package:ecoearn_app/data/app_database.dart';
import 'package:ecoearn_app/data/student.dart';
import 'package:ecoearn_app/data/student_repository.dart';
import 'package:ecoearn_app/serial/device_event.dart';
import 'package:ecoearn_app/serial/serial_connection.dart';
import 'package:ecoearn_app/serial/simulator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('demo mode plays card tap, then a result and bin level, all simulated', () async {
    final db = await AppDatabase.open(inMemoryDatabasePath);
    final students = StudentRepository(db);
    await students.save(const Student(studentNo: '1', name: 'Juan Dela Cruz', rfidUid: 'A3F29B11'));
    final connection = SerialConnection();
    final simulator = Simulator(
      connection: connection,
      students: students,
      processing: const Duration(milliseconds: 50),
      pauseBetween: const Duration(milliseconds: 200),
    );
    final received = <DeviceEvent>[];
    final subscription = connection.events.listen(received.add);

    simulator.start();
    await Future.delayed(const Duration(milliseconds: 120)); // one deposit done, still pausing
    simulator.stop();
    await Future.delayed(const Duration(milliseconds: 300)); // a stopped demo sends nothing more

    expect(received.first, isA<BootEvent>());
    expect(received.whereType<CardEvent>(), hasLength(1));
    expect(received.whereType<StageEvent>().map((e) => e.stage),
        ['ready', 'crushing', 'draining', 'dropping', 'weighing', 'tipping']);
    expect(received.where((e) => e is WeightEvent || e is RejectEvent), hasLength(1));
    expect(received.last, isA<BinEvent>());
    expect(received.every((e) => e.simulated), isTrue);
    expect(simulator.running, isFalse);

    await subscription.cancel();
    simulator.dispose();
    connection.dispose();
    await db.close();
  });

  test('stopping mid-deposit clears "processing" on the screens', () async {
    final db = await AppDatabase.open(inMemoryDatabasePath);
    final connection = SerialConnection();
    final simulator = Simulator(
      connection: connection,
      students: StudentRepository(db),
      processing: const Duration(milliseconds: 200),
    );
    final received = <DeviceEvent>[];
    final subscription = connection.events.listen(received.add);

    simulator.start();
    await Future.delayed(const Duration(milliseconds: 50));
    simulator.stop();
    await Future.delayed(const Duration(milliseconds: 300));

    expect(received.last, isA<BootEvent>());
    expect(received.where((e) => e is WeightEvent || e is RejectEvent), isEmpty);

    await subscription.cancel();
    simulator.dispose();
    connection.dispose();
    await db.close();
  });
}
