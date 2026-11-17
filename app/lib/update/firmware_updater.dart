import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../live/live_session.dart';
import '../serial/auto_connect.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';
import 'updater.dart';

enum FlashState { idle, preparing, waitingForBoot, writing, restarting, done, failed }

/// Updates the ESP32's firmware from inside the app. Each release ships the
/// matching firmware next to the program (firmware/ecoearn.bin, version.txt)
/// with Espressif's esptool. When the connected machine reports an older
/// version, the admin clicks "Update machine", holds BOOT when asked, and the
/// app flashes it. Only the program area (0x10000) is written, so the saved
/// scale calibration and points rate stay.
class FirmwareUpdater extends ChangeNotifier {
  FirmwareUpdater({
    required SerialConnection connection,
    required AutoConnect autoConnect,
    required LiveSession session,
    String? firmwareFolder,
  })  : _connection = connection,
        _autoConnect = autoConnect,
        _session = session,
        _folder = firmwareFolder ?? p.join(p.dirname(Platform.resolvedExecutable), 'firmware') {
    _bundledVersion = _readBundledVersion();
    _events = connection.events.listen(_onEvent);
    connection.addListener(_onConnection);
  }

  final SerialConnection _connection;
  final AutoConnect _autoConnect;
  final LiveSession _session;
  final String _folder;
  late final StreamSubscription<DeviceEvent> _events;

  String? _bundledVersion;
  bool _wasConnected = false;
  bool _asked = false; // asked the machine for its version since connecting
  FlashState _state = FlashState.idle;
  double? _progress;
  String? _message;
  final List<String> _log = [];

  /// The firmware version this app carries; null when it carries none (a developer run).
  String? get bundledVersion => _bundledVersion;

  /// What the connected machine reported; null until it answers.
  String? get machineVersion => _connection.isConnected ? _session.firmwareVersion : null;

  FlashState get state => _state;
  double? get progress => _progress;
  String? get message => _message;
  bool get busy => const {FlashState.preparing, FlashState.waitingForBoot, FlashState.writing, FlashState.restarting}
      .contains(_state);

  /// The connected machine runs older firmware than the app carries (or so old
  /// that it can't say which, after being asked).
  bool get updateAvailable {
    final bundled = _bundledVersion;
    if (bundled == null || !_connection.isConnected || busy) return false;
    final machine = _session.firmwareVersion;
    if (machine == null || machine == 'demo') return _asked && machine == null;
    return isNewer(bundled, machine);
  }

  String? _readBundledVersion() {
    try {
      final version = File(p.join(_folder, 'version.txt')).readAsStringSync().trim();
      final ok = version.isNotEmpty && File(p.join(_folder, 'ecoearn.bin')).existsSync() &&
          File(p.join(_folder, 'esptool.exe')).existsSync();
      return ok ? version : null;
    } catch (_) {
      return null;
    }
  }

  void _onConnection() {
    final connected = _connection.isConnected;
    if (connected && !_wasConnected) {
      _asked = false;
      if (_state == FlashState.failed || _state == FlashState.done) _state = FlashState.idle;
      unawaited(_askVersion());
    }
    _wasConnected = connected;
    notifyListeners();
  }

  // Firmware 0.3.2+ answers "version" with its boot message; older firmware
  // ignores it. Ask a few times: a board that restarts when the port opens
  // (some drivers do that) needs a moment before it listens.
  Future<void> _askVersion() async {
    for (final wait in const [Duration(milliseconds: 600), Duration(seconds: 2), Duration(seconds: 3)]) {
      await Future<void>.delayed(wait);
      if (!_connection.isConnected) return;
      if (_session.firmwareVersion != null) break;
      _connection.send('version');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    _asked = true;
    notifyListeners();
  }

  void _onEvent(DeviceEvent event) {
    if (event is BootEvent && !event.simulated) notifyListeners();
  }

  /// Flashes the bundled firmware onto the machine.
  Future<void> flash() async {
    final port = _connection.portName;
    final bundled = _bundledVersion;
    if (port == null || bundled == null || busy) return;

    _set(FlashState.preparing, 'Getting the machine ready…');
    _log.clear();
    _autoConnect.pause();
    _connection.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 800)); // let Windows release the port

    final int exitCode;
    try {
      final process = await Process.start(p.join(_folder, 'esptool.exe'), [
        // 115200: slower than 460800 but every driver, cable and USB port copes with it.
        '--chip', 'esp32', '--port', port, '--baud', '115200',
        '--before', 'default-reset', '--after', 'hard-reset',
        'write-flash', '-z', '0x10000', p.join(_folder, 'ecoearn.bin'),
      ]);
      final killer = Timer(const Duration(minutes: 3), process.kill);
      final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true));
      final err = process.stderr.transform(const Utf8Decoder(allowMalformed: true));
      await Future.wait([out.forEach(_onOutput), err.forEach(_onOutput)]);
      exitCode = await process.exitCode;
      killer.cancel();
    } catch (e) {
      _finish(false, 'Could not start the firmware tool ($e). If antivirus removed esptool.exe, '
          'reinstall EcoEarn or allow it.');
      return;
    }

    if (exitCode == 0) {
      _set(FlashState.restarting, 'Restarting the machine…');
      _finish(true, 'Machine updated to firmware $bundled.');
    } else {
      final text = _log.join('\n');
      _finish(
        false,
        text.contains('Failed to connect') || text.contains('Wrong boot mode') || text.contains('No serial data')
            ? 'The machine didn\'t enter upload mode. Press "Update machine" again and hold the BOOT button '
                'on the ESP32 as soon as "Hold BOOT" appears, until writing starts.'
            : text.contains('could not open port') || text.contains('Access is denied')
                ? 'Another program is using $port (is the Arduino Serial Monitor open?). Close it and try again.'
                : 'The update didn\'t finish (code $exitCode). The machine keeps its old firmware; try again. '
                    'Details: ${_log.reversed.take(2).toList().reversed.join(' / ')}',
      );
    }
  }

  void _onOutput(String chunk) {
    for (final line in chunk.split(RegExp(r'[\r\n]+'))) {
      final text = line.trim();
      if (text.isEmpty) continue;
      _log.add(text);
      if (text.startsWith('Connecting')) {
        _set(FlashState.waitingForBoot, 'Hold the BOOT button on the ESP32 now…');
      } else {
        final percent = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(text);
        if (percent != null && (text.contains('Writing') || _state == FlashState.writing)) {
          _progress = (double.parse(percent.group(1)!) / 100).clamp(0, 1);
          _set(FlashState.writing, 'Writing the new firmware… you can let go of BOOT.');
        }
      }
    }
  }

  void _set(FlashState state, String message) {
    _state = state;
    _message = message;
    notifyListeners();
  }

  void _finish(bool ok, String message) {
    _state = ok ? FlashState.done : FlashState.failed;
    _message = message;
    _progress = null;
    // Reconnect (the app asks the machine for its version again on connect).
    _autoConnect.resume();
    notifyListeners();
  }

  @override
  void dispose() {
    _events.cancel();
    _connection.removeListener(_onConnection);
    super.dispose();
  }
}
