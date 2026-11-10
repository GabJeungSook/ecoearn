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

  static const _pollEvery = Duration(milliseconds: 50);

  final _events = StreamController<DeviceEvent>.broadcast();
  final _notes = StreamController<String>.broadcast();
  SerialPort? _port;
  // Not libserialport's SerialPortReader: its background isolate loops without
  // ever returning to its event loop, so it can't be stopped and kept reading
  // the port after Disconnect freed it ("Debug Assertion Failed" heap crash).
  // A timer on this isolate reads whatever has arrived instead.
  Timer? _poll;
  StreamController<List<int>>? _bytes;

  String? _portName;
  String? _error;

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

  void connect(String name) {
    _close();
    _error = null;

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
    // The port now owns the config and frees it in port.dispose(). Freeing it
    // here as well was a double free: the "Debug Assertion Failed" heap crash
    // on Disconnect.
    port.config = config;

    _port = port;
    _portName = name;
    final bytes = StreamController<List<int>>();
    _bytes = bytes;
    // The line subscription ends by itself when the byte stream is closed.
    bytes.stream.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen(_onLine);
    _poll = Timer.periodic(_pollEvery, (_) => _readAvailable(port, name));
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

  void _readAvailable(SerialPort port, String name) {
    final waiting = port.bytesAvailable; // negative when the port is gone (cable unplugged)
    if (waiting < 0) {
      _fail('Lost connection to $name. Is the USB cable unplugged?');
      return;
    }
    if (waiting == 0) return;
    try {
      _bytes?.add(port.read(waiting));
    } on SerialPortError catch (e) {
      _fail('Lost connection to $name ($e). Is the USB cable unplugged?');
    }
  }

  void _close() {
    _poll?.cancel();
    _poll = null;
    unawaited(_bytes?.close());
    _bytes = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }

  @override
  void dispose() {
    _close();
    _events.close();
    _notes.close();
    super.dispose();
  }
}
