import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/account.dart';
import '../auth/auth_service.dart';
import 'serial_connection.dart';

/// Connects to the machine by itself while an admin or display account is
/// signed in (as soon as the ESP32 is plugged in, and again after it is
/// unplugged and back), and disconnects when they sign out.
///
/// A Disconnect clicked on the Live screen pauses it, so it doesn't fight the
/// admin; clicking Connect or signing in again resumes it.
class AutoConnect {
  AutoConnect({required SerialConnection connection, required AuthService auth})
      : _connection = connection,
        _auth = auth {
    auth.addListener(_onAuth);
    _onAuth();
  }

  static const _checkEvery = Duration(seconds: 3);

  final SerialConnection _connection;
  final AuthService _auth;
  Timer? _timer;
  Role? _role;
  bool _paused = false;

  void _onAuth() {
    final role = _auth.current?.role;
    if (role == _role) return;
    final wasSignedIn = _role != null;
    _role = role;

    if (role == Role.admin || role == Role.display) {
      _paused = false;
      _timer ??= Timer.periodic(_checkEvery, (_) => _check());
      _check();
    } else {
      _timer?.cancel();
      _timer = null;
      if (wasSignedIn && _connection.isConnected) _connection.disconnect();
    }
  }

  /// The admin clicked Disconnect: stay disconnected until [resume].
  void pause() => _paused = true;

  /// The admin clicked Connect: reconnect by itself again after an unplug.
  void resume() => _paused = false;

  void _check() {
    if (_paused || _connection.isConnected) return;
    try {
      final port = SerialConnection.listPorts().where((p) => p.looksLikeEsp32).firstOrNull;
      if (port != null) _connection.connect(port.name);
    } catch (e) {
      debugPrint('Could not list serial ports: $e'); // try again on the next check
    }
  }

  void dispose() {
    _timer?.cancel();
    _auth.removeListener(_onAuth);
  }
}
