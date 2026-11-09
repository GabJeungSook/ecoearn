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

  final _events = StreamController<DeviceEvent>.broadcast();
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<String>? _lines;

  String? _portName;
  String? _error;

  Stream<DeviceEvent> get events => _events.stream;
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
    port.config = config;
    config.dispose();

    _port = port;
    _portName = name;
    _reader = SerialPortReader(port);
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
    final event = DeviceEvent.tryParse(line);
    if (event != null) _events.add(event);
  }

  void _fail(String message) {
    _close();
    _error = message;
    notifyListeners();
  }

  void _close() {
    unawaited(_lines?.cancel());
    _lines = null;
    _reader?.close();
    _reader = null;
    _port?.close();
    _port?.dispose();
    _port = null;
  }

  @override
  void dispose() {
    _close();
    _events.close();
    super.dispose();
  }
}
