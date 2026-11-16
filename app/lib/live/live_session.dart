import 'dart:async';

import 'package:flutter/foundation.dart';

import '../serial/device_event.dart';

/// Keep in sync with BIN_FULL_PERCENT in firmware/ecoearn/config.h.
const binFullPercent = 90;

/// What the live screen shows: the latest machine state and running totals
/// since the app was opened. Nothing here is saved yet.
class LiveSession extends ChangeNotifier {
  LiveSession(Stream<DeviceEvent> events) {
    _subscription = events.listen(_onEvent);
  }

  static const maxLogEntries = 300;

  late final StreamSubscription<DeviceEvent> _subscription;

  /// Newest first.
  final List<DeviceEvent> log = [];

  String? firmwareVersion;

  /// Card that was tapped and whose bottle is still being processed.
  String? processingUid;

  /// What the machine is doing for [processingUid], from its stage events
  /// (null until the first one, or with older firmware).
  StageEvent? stage;

  /// The last [WeightEvent] or [RejectEvent].
  DeviceEvent? lastResult;

  int? binLevel;
  int bottles = 0;
  int points = 0;
  int rejects = 0;

  void _onEvent(DeviceEvent event) {
    // Steps are shown on the processing screens, not listed in the log.
    if (event is! StageEvent) {
      log.insert(0, event);
      if (log.length > maxLogEntries) log.removeLast();
    }

    switch (event) {
      case BootEvent(:final version):
        firmwareVersion = version;
        processingUid = null;
        stage = null;
      case CardEvent(:final uid):
        processingUid = uid;
        stage = null;
      case StageEvent(:final uid):
        // "tipping" comes after the result; only steps of the deposit in progress count.
        if (uid == processingUid) stage = event;
      case WeightEvent(points: final earned):
        lastResult = event;
        processingUid = null;
        stage = null;
        bottles++;
        points += earned;
      case RejectEvent():
        lastResult = event;
        processingUid = null;
        stage = null;
        rejects++;
      case BinEvent(:final level):
        binLevel = level;
      case ScanEvent() || UnknownEvent():
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
