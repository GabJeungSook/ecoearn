import 'dart:async';

import 'package:flutter/foundation.dart';

import '../serial/device_event.dart';
import '../serial/serial_connection.dart';

/// Keep in sync with BIN_FULL_PERCENT in firmware/ecoearn/config.h.
const binFullPercent = 90;

/// What the live screen shows: the latest machine state and running totals
/// since the app was opened. Nothing here is saved yet.
class LiveSession extends ChangeNotifier {
  LiveSession(SerialConnection connection) {
    _subscription = connection.events.listen(_onEvent);
  }

  static const maxLogEntries = 300;

  late final StreamSubscription<DeviceEvent> _subscription;

  /// Newest first.
  final List<DeviceEvent> log = [];

  String? firmwareVersion;

  /// Card that was tapped and whose bottle is still being processed.
  String? processingUid;

  /// The last [WeightEvent] or [RejectEvent].
  DeviceEvent? lastResult;

  int? binLevel;
  int bottles = 0;
  int points = 0;
  int rejects = 0;

  void _onEvent(DeviceEvent event) {
    log.insert(0, event);
    if (log.length > maxLogEntries) log.removeLast();

    switch (event) {
      case BootEvent(:final version):
        firmwareVersion = version;
        processingUid = null;
      case CardEvent(:final uid):
        processingUid = uid;
      case WeightEvent(points: final earned):
        lastResult = event;
        processingUid = null;
        bottles++;
        points += earned;
      case RejectEvent():
        lastResult = event;
        processingUid = null;
        rejects++;
      case BinEvent(:final level):
        binLevel = level;
      case UnknownEvent():
        break;
    }
    notifyListeners();
  }

  void clear() {
    log.clear();
    lastResult = null;
    bottles = 0;
    points = 0;
    rejects = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
