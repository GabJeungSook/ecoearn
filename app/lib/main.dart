import 'package:flutter/material.dart';

import 'live/live_screen.dart';
import 'live/live_session.dart';
import 'serial/serial_connection.dart';

void main() => runApp(const EcoEarnApp());

class EcoEarnApp extends StatefulWidget {
  const EcoEarnApp({super.key});

  @override
  State<EcoEarnApp> createState() => _EcoEarnAppState();
}

class _EcoEarnAppState extends State<EcoEarnApp> {
  final _connection = SerialConnection();
  late final _session = LiveSession(_connection);

  @override
  void dispose() {
    _session.dispose();
    _connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoEarn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green),
      home: LiveScreen(connection: _connection, session: _session),
    );
  }
}
