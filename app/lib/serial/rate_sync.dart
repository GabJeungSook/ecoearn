import 'dart:async';

import '../data/point_rules.dart';
import 'device_event.dart';
import 'serial_connection.dart';

/// Keeps the machine's points rate equal to the app's setting: sends `rate N`
/// when the machine connects, restarts with a different rate, or when the
/// admin changes it. The machine saves it, so it also holds without the laptop.
class RateSync {
  RateSync({required SerialConnection connection, required PointRules rules})
      : _connection = connection,
        _rules = rules {
    _events = connection.events.listen(_onEvent);
    connection.addListener(_onConnection);
    rules.addListener(_send);
  }

  final SerialConnection _connection;
  final PointRules _rules;
  late final StreamSubscription<DeviceEvent> _events;
  bool _wasConnected = false;

  void _onEvent(DeviceEvent event) {
    // Older firmware doesn't report a rate (null); it gets one on connect anyway.
    if (event is BootEvent && !event.simulated && event.gramsPerPoint != _rules.gramsPerPoint) _send();
  }

  void _onConnection() {
    final connected = _connection.isConnected;
    if (connected && !_wasConnected) _send();
    _wasConnected = connected;
  }

  void _send() {
    if (_connection.isConnected) _connection.send('rate ${_rules.gramsPerPoint}');
  }

  void dispose() {
    _events.cancel();
    _connection.removeListener(_onConnection);
    _rules.removeListener(_send);
  }
}
