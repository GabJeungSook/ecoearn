import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/app_database.dart';
import 'data/deposit_recorder.dart';
import 'data/reports.dart';
import 'data/student_repository.dart';
import 'live/live_screen.dart';
import 'live/live_session.dart';
import 'reports/reports_screen.dart';
import 'serial/serial_connection.dart';
import 'students/students_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final databasePath = await AppDatabase.defaultPath();
  final db = await AppDatabase.open(databasePath);
  final students = StudentRepository(db);
  await students.load();
  runApp(EcoEarnApp(db: db, databasePath: databasePath, students: students));
}

class EcoEarnApp extends StatefulWidget {
  const EcoEarnApp({
    super.key,
    required this.db,
    required this.databasePath,
    required this.students,
  });

  final Database db;
  final String databasePath;
  final StudentRepository students;

  @override
  State<EcoEarnApp> createState() => _EcoEarnAppState();
}

class _EcoEarnAppState extends State<EcoEarnApp> {
  final _connection = SerialConnection();
  late final _session = LiveSession(_connection);
  late final _recorder = DepositRecorder(
    db: widget.db,
    students: widget.students,
    events: _connection.events,
  );
  late final _reports = Reports(widget.db);
  int _screen = 0;

  @override
  void dispose() {
    _recorder.dispose();
    _session.dispose();
    _connection.dispose();
    widget.students.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoEarn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green),
      home: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _screen,
              onDestinationSelected: (i) => setState(() => _screen = i),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.sensors), label: Text('Live')),
                NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Students')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('Reports')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // IndexedStack keeps each screen's state (port list, search) when switching.
              child: IndexedStack(
                index: _screen,
                children: [
                  LiveScreen(
                    connection: _connection,
                    session: _session,
                    students: widget.students,
                    recorder: _recorder,
                  ),
                  StudentsScreen(
                    students: widget.students,
                    connection: _connection,
                    databasePath: widget.databasePath,
                  ),
                  ReportsScreen(reports: _reports, students: widget.students),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
