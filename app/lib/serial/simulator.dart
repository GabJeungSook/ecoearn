import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../data/point_rules.dart';
import '../data/student_repository.dart';
import 'device_event.dart';
import 'serial_connection.dart';

/// Demo mode: pretends to be the machine so the screens can be shown without
/// an ESP32. It feeds made-up events into [SerialConnection] exactly where real
/// ones arrive. They are marked `simulated`, so nothing is saved to the database.
class Simulator extends ChangeNotifier {
  Simulator({
    required SerialConnection connection,
    required StudentRepository students,
    PointRules? rules,
    this.processing = const Duration(milliseconds: 8500), // crush + drain + weigh, as on the machine
    this.pauseBetween = const Duration(seconds: 7), // result stays on screen, then the next student
  })  : _connection = connection,
        _students = students,
        _rules = rules;

  // Same rules as the firmware (firmware/ecoearn/config.h).
  static const _maxItemGrams = 80;

  final Duration processing;
  final Duration pauseBetween;

  final SerialConnection _connection;
  final StudentRepository _students;
  final PointRules? _rules; // the admin's points rate; firmware default without it
  final _random = Random();

  bool _running = false;
  int _run = 0; // a new value cancels a deposit that is still in progress
  int _binLevel = 12;
  bool _midDeposit = false; // a card was tapped and no result sent yet

  /// True while demo deposits keep coming, one after another.
  bool get running => _running;

  void start() {
    if (_running) return;
    _running = true;
    notifyListeners();
    _emit(BootEvent(version: 'demo', simulated: true));
    _emit(BinEvent(level: _binLevel, simulated: true));
    _loop(++_run);
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _run++;
    // A boot event clears "processing" on the screens, like a machine restart would.
    if (_midDeposit) _emit(BootEvent(version: 'demo', simulated: true));
    _midDeposit = false;
    notifyListeners();
  }

  void toggle() => _running ? stop() : start();

  Future<void> _loop(int run) async {
    while (run == _run) {
      await _deposit(run);
      await Future.delayed(pauseBetween);
    }
  }

  /// One student taps, waits for the machine, and gets a result.
  Future<void> _deposit(int run) async {
    final withCards = _students.students.where((s) => s.rfidUid != null).toList();
    // Now and then an unregistered card, to show that screen too.
    final uid = withCards.isEmpty || _random.nextInt(8) == 0
        ? 'DE0000${_random.nextInt(90) + 10}'
        : withCards[_random.nextInt(withCards.length)].rfidUid!;

    _emit(CardEvent(uid: uid, simulated: true));
    _midDeposit = true;
    await Future.delayed(processing);
    if (run != _run) return;
    _midDeposit = false;

    final roll = _random.nextInt(10);
    if (roll == 0) {
      _emit(RejectEvent(uid: uid, reason: 'too_heavy', grams: 95.0 + _random.nextInt(60), simulated: true));
    } else if (roll == 1) {
      _emit(RejectEvent(uid: uid, reason: 'no_item', grams: 0, simulated: true));
    } else {
      final grams = 12 + _random.nextInt(_maxItemGrams - 20); // 12-71 g, a crushed bottle
      final gramsPerPoint = _rules?.gramsPerPoint ?? AppDatabase.defaultGramsPerPoint;
      _emit(WeightEvent(
        uid: uid,
        grams: grams.toDouble(),
        points: grams ~/ gramsPerPoint,
        gramsPerPoint: gramsPerPoint,
        simulated: true,
      ));
    }

    _binLevel += 3 + _random.nextInt(5);
    if (_binLevel >= 95) _binLevel = 8; // pretend staff emptied it
    _emit(BinEvent(level: _binLevel, simulated: true));
  }

  void _emit(DeviceEvent event) => _connection.inject(event);

  @override
  void dispose() {
    _run++;
    super.dispose();
  }
}
