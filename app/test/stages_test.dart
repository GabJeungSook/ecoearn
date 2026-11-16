import 'dart:async';

import 'package:ecoearn_app/live/live_session.dart';
import 'package:ecoearn_app/live/stages.dart';
import 'package:ecoearn_app/serial/device_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stage events parse, with or without a duration', () {
    final e = DeviceEvent.tryParse('{"event":"stage","uid":"47A87362","stage":"crushing","ms":58000}');
    expect(e, isA<StageEvent>().having((s) => s.stage, 'stage', 'crushing').having((s) => s.expectedMs, 'ms', 58000));
    expect(MachineStage.of(e as StageEvent), MachineStage.crushing);
    expect(
        DeviceEvent.tryParse('{"event":"stage","uid":"X","stage":"weighing"}'),
        isA<StageEvent>().having((s) => s.expectedMs, 'ms', null));
  });

  test('the session follows the steps of the deposit in progress only', () async {
    final events = StreamController<DeviceEvent>();
    final session = LiveSession(events.stream);
    Future<void> send(DeviceEvent e) async {
      events.add(e);
      await pumpEventQueue();
    }

    await send(CardEvent(uid: 'A'));
    expect(session.stage, isNull);
    await send(StageEvent(uid: 'A', stage: 'crushing', expectedMs: 1500));
    expect(MachineStage.of(session.stage), MachineStage.crushing);
    expect(session.log.whereType<StageEvent>(), isEmpty); // steps don't clutter the log
    await send(WeightEvent(uid: 'A', grams: 30, points: 3));
    expect(session.stage, isNull);
    await send(StageEvent(uid: 'A', stage: 'tipping', expectedMs: 0)); // after the result: ignored
    expect(session.stage, isNull);

    session.dispose();
    await events.close();
  });

  test('progress moves forward through the steps and never reaches 100% on its own', () {
    final t0 = DateTime(2026, 11, 17, 10);
    StageEvent at(String stage, int ms) => StageEvent(uid: 'A', stage: stage, expectedMs: ms, receivedAt: t0);
    final values = [
      depositProgress(null, t0),
      depositProgress(at('ready', 4000), t0.add(const Duration(seconds: 2))),
      depositProgress(at('crushing', 58000), t0.add(const Duration(seconds: 30))),
      depositProgress(at('draining', 5000), t0.add(const Duration(seconds: 4))),
      depositProgress(at('weighing', 3000), t0.add(const Duration(minutes: 5))),
    ];
    for (var i = 1; i < values.length; i++) {
      expect(values[i], greaterThan(values[i - 1]));
    }
    expect(values.last, lessThan(0.97));
  });
}
