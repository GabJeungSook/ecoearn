import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'device_event.dart';

class PortInfo {
  const PortInfo(this.name, this.description);

  final String name; // e.g. COM3
  final String description; // e.g. USB-SERIAL CH340 (COM3)

  /// True for the USB chips used on ESP32 boards.
  bool get looksLikeEsp32 =>
      description.contains('CH340') ||
      description.contains('CH341') ||
      description.contains('CP210');
}

/// Owns the USB serial link to the ESP32 and turns incoming lines into
/// [DeviceEvent]s.
class SerialConnection extends ChangeNotifier {
  static const baudRate = 115200;

  // The background reader wakes at least this often, so it has let go of a
  // port this long after being stopped.
  static const _readerTimeout = Duration(milliseconds: 200);
  static const _readerStopped = Duration(milliseconds: 600);

  final _events = StreamController<DeviceEvent>.broadcast();
  final _notes = StreamController<String>.broadcast();
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<String>? _lines;

  String? _portName;
  String? _error;
  Future<void> _closing = Future.value();
  bool _connecting = false;

  Stream<DeviceEvent> get events => _events.stream;

  /// The firmware's lines for people (those starting with "# "), without the
  /// "# ", e.g. "Weight: 72.0 g" or "Scale zeroed.". Used by the scale calibration.
  Stream<String> get notes => _notes.stream;
  bool get isConnected => _port != null;
  String? get portName => _portName;

  /// Why the last connection attempt failed or dropped, if it did.
  String? get error => _error;

  static List<PortInfo> listPorts() => [
        for (final name in SerialPort.availablePorts) _describe(name),
      ];

  static PortInfo _describe(String name) {
    final port = SerialPort(name);
    try {
      return PortInfo(name, port.description ?? name);
    } finally {
      port.dispose();
    }
  }

  /// Opens [name]. Waits for a port being closed to be fully released first.
  Future<void> connect(String name) async {
    if (_connecting) return;
    _connecting = true;
    try {
      _close();
      _error = null;
      await _closing;
      _open(name);
    } finally {
      _connecting = false;
    }
  }

  void _open(String name) {
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      final reason = SerialPort.lastError?.message ?? 'unknown error';
      port.dispose();
      _fail('Could not open $name ($reason). '
          'If the Arduino IDE Serial Monitor is open, close it first.');
      return;
    }

    final config = SerialPortConfig()
      ..baudRate = baudRate
      ..bits = 8
      ..stopBits = 1
      ..parity = SerialPortParity.none
      ..setFlowControl(SerialPortFlowControl.none)
      // Leave the ESP32's EN/BOOT lines alone so opening the port doesn't reset it.
      ..dtr = SerialPortDtr.off
      ..rts = SerialPortRts.off;
    port.config = config;
    config.dispose();

    _port = port;
    _portName = name;
    _reader = SerialPortReader(port, timeout: _readerTimeout.inMilliseconds);
    _lines = _reader!.stream
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object e) => _fail('Lost connection to $name ($e). Is the USB cable unplugged?'),
          onDone: () => _fail('Lost connection to $name.'),
        );
    notifyListeners();
  }

  void disconnect() {
    _close();
    _error = null;
    notifyListeners();
  }

  /// Sends one command line to the ESP32, e.g. `register`. Returns false if
  /// not connected or the write failed.
  bool send(String command) {
    final port = _port;
    if (port == null) return false;
    try {
      final bytes = Uint8List.fromList(utf8.encode('$command\n'));
      return port.write(bytes, timeout: 500) == bytes.length;
    } on SerialPortError {
      return false;
    }
  }

  /// Feeds an event in as if the ESP32 had sent it (used by the demo simulator).
  void inject(DeviceEvent event) => _events.add(event);

  void _onLine(String line) {
    if (line.startsWith('# ')) {
      _notes.add(line.substring(2).trim());
      return;
    }
    final event = DeviceEvent.tryParse(line);
    if (event != null) _events.add(event);
  }

  void _fail(String message) {
    _close();
    _error = message;
    notifyListeners();
  }

  // The reader runs in a background isolate that may be inside a native read
  // when it is stopped. Freeing the port at once made it use freed memory (a
  // "Debug Assertion Failed" heap crash on Disconnect), so the port is closed
  // only after the reader has certainly stopped.
  void _close() {
    unawaited(_lines?.cancel());
    _lines = null;
    _reader?.close();
    _reader = null;
    final port = _port;
    _port = null;
    if (port != null) {
      _closing = Future.delayed(_readerStopped, () {
        port.close();
        port.dispose();
      });
    }
  }

  @override
  void dispose() {
    _close();
    _events.close();
    _notes.close();
    super.dispose();
  }
}
