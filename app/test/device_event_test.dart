import 'package:ecoearn_app/live/live_screen.dart';
import 'package:ecoearn_app/serial/device_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceEvent.tryParse', () {
    test('parses every firmware event', () {
      expect(DeviceEvent.tryParse('{"event":"boot","version":"0.1.0"}'),
          isA<BootEvent>().having((e) => e.version, 'version', '0.1.0'));
      expect(DeviceEvent.tryParse('{"event":"card","uid":"A3F29B11"}'),
          isA<CardEvent>().having((e) => e.uid, 'uid', 'A3F29B11'));
      expect(DeviceEvent.tryParse('{"event":"scan","uid":"47A87362"}'),
          isA<ScanEvent>().having((e) => e.uid, 'uid', '47A87362'));
      expect(
          DeviceEvent.tryParse('{"event":"weight","uid":"A3F29B11","grams":39,"points":3}'),
          isA<WeightEvent>()
              .having((e) => e.grams, 'grams', 39)
              .having((e) => e.points, 'points', 3));
      expect(
          DeviceEvent.tryParse('{"event":"reject","uid":"A3F29B11","reason":"too_heavy","grams":120}'),
          isA<RejectEvent>().having((e) => e.reason, 'reason', 'too_heavy').having((e) => e.detail, 'detail', null));
      expect(
          DeviceEvent.tryParse(
              '{"event":"reject","uid":"A3F29B11","reason":"mechanism","grams":0,"detail":"scale_not_calibrated"}'),
          isA<RejectEvent>().having((e) => e.detail, 'detail', 'scale_not_calibrated'));
      expect(DeviceEvent.tryParse('{"event":"bin","level":64}'),
          isA<BinEvent>().having((e) => e.level, 'level', 64));
    });

    test('accepts decimal grams from a real scale', () {
      final e = DeviceEvent.tryParse('{"event":"weight","uid":"X","grams":18.5,"points":1}');
      expect(e, isA<WeightEvent>().having((e) => e.grams, 'grams', 18.5));
    });

    test('ignores ESP32 startup text and garbled bytes', () {
      expect(DeviceEvent.tryParse('ets Jul 29 2019 12:21:46'), isNull);
      expect(DeviceEvent.tryParse('rst:0x1 (POWERON_RESET),boot:0x13'), isNull);
      expect(DeviceEvent.tryParse('# Put the item on the scale now.'), isNull);
      expect(DeviceEvent.tryParse('���'), isNull);
      expect(DeviceEvent.tryParse('{"event":"card","uid":'), isNull);
      expect(DeviceEvent.tryParse(''), isNull);
    });

    test('keeps unknown or incomplete events as UnknownEvent', () {
      expect(DeviceEvent.tryParse('{"event":"lid","open":true}'),
          isA<UnknownEvent>().having((e) => e.name, 'name', 'lid'));
      expect(DeviceEvent.tryParse('{"event":"weight","uid":"X"}'), isA<UnknownEvent>());
    });
  });

  test('describeEvent reads naturally', () {
    expect(describeEvent(WeightEvent(uid: 'A3F29B11', grams: 39, points: 3)),
        'Deposit: A3F29B11, 39 g → 3 points');
    expect(describeEvent(RejectEvent(uid: 'A3F29B11', reason: 'too_heavy', grams: 120)),
        'Rejected: A3F29B11, too heavy (120 g)');
    expect(describeEvent(RejectEvent(uid: 'A3F29B11', reason: 'bin_full', grams: 0)),
        'Rejected: A3F29B11, bin is full');
    expect(describeEvent(CardEvent(uid: 'A3F29B11'), (uid) => 'Juan Dela Cruz ($uid)'),
        'Card tapped: Juan Dela Cruz (A3F29B11)');
  });
}
