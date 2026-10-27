import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../serial/device_event.dart';
import 'student.dart';
import 'student_repository.dart';

/// Saves every processed bottle the ESP32 reports (accepted or rejected) as
/// a row in `deposits`, credited to the student who owns the card.
class DepositRecorder extends ChangeNotifier {
  DepositRecorder({
    required Database db,
    required StudentRepository students,
    required Stream<DeviceEvent> events,
  })  : _db = db,
        _students = students {
    _subscription = events.listen(_onEvent);
  }

  final Database _db;
  final StudentRepository _students;
  late final StreamSubscription<DeviceEvent> _subscription;

  // Writes run one at a time, in the order the events arrived.
  Future<void> _pending = Future.value();

  String? _error;

  /// Set when a deposit could not be saved.
  String? get error => _error;

  void _onEvent(DeviceEvent event) {
    final row = switch (event) {
      WeightEvent(:final uid, :final grams, :final points) => _row(event, uid, grams, points, null),
      RejectEvent(:final uid, :final grams, :final reason) => _row(event, uid, grams, 0, reason),
      _ => null,
    };
    if (row != null) _pending = _pending.then((_) => _save(row));
  }

  Map<String, Object?> _row(DeviceEvent event, String uid, double grams, int points, String? rejectReason) {
    final cardUid = Student.normalizeUid(uid) ?? uid;
    return {
      'occurred_at': event.receivedAt.toIso8601String(),
      'rfid_uid': cardUid,
      'student_id': _students.byUid(cardUid)?.id,
      'grams': grams,
      'points': points,
      'reject_reason': rejectReason,
      'source': 'live',
    };
  }

  Future<void> _save(Map<String, Object?> row) async {
    try {
      await _db.insert('deposits', row);
      await _students.load();
      if (_error != null) {
        _error = null;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Could not save a deposit: $e';
      notifyListeners();
    }
  }

  /// Completes once every deposit received so far has been written.
  Future<void> flush() => _pending;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
