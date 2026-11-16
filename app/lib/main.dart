import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'auth/account.dart';
import 'auth/auth_service.dart';
import 'auth/login_screen.dart';
import 'data/app_database.dart';
import 'data/deposit_recorder.dart';
import 'data/officer_data.dart';
import 'data/point_rules.dart';
import 'data/reports.dart';
import 'data/student_repository.dart';
import 'live/live_session.dart';
import 'serial/auto_connect.dart';
import 'serial/rate_sync.dart';
import 'serial/serial_connection.dart';
import 'serial/simulator.dart';
import 'shell/admin_shell.dart';
import 'shell/display_kiosk.dart';
import 'shell/officer_shell.dart';
import 'sound/card_beeper.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('EcoEarn');
  await windowManager.setMinimumSize(const Size(1100, 700));
  await windowManager.setFullScreen(true); // no title bar; F11 toggles

  final databasePath = await AppDatabase.defaultPath();
  final db = await AppDatabase.open(databasePath);
  final students = StudentRepository(db);
  await students.load();
  final auth = AuthService(db);
  await auth.load();
  final rules = PointRules(db);
  await rules.load();
  final officerData = OfficerData(p.dirname(databasePath));
  await officerData.open();

  runApp(EcoEarnApp(
    db: db,
    databasePath: databasePath,
    students: students,
    auth: auth,
    rules: rules,
    officerData: officerData,
  ));
}

class EcoEarnApp extends StatefulWidget {
  const EcoEarnApp({
    super.key,
    required this.db,
    required this.databasePath,
    required this.students,
    required this.auth,
    required this.rules,
    required this.officerData,
  });

  final Database db;
  final String databasePath;
  final StudentRepository students;
  final AuthService auth;
  final PointRules rules;
  final OfficerData officerData;

  @override
  State<EcoEarnApp> createState() => _EcoEarnAppState();
}

class _EcoEarnAppState extends State<EcoEarnApp> {
  // The serial link and deposit recording run whoever is signed in (even on
  // the sign-in screen), so the machine never stops saving bottles.
  final _connection = SerialConnection();
  late final _session = LiveSession(_connection.events);
  late final _recorder = DepositRecorder(
    db: widget.db,
    students: widget.students,
    events: _connection.events,
    rules: widget.rules,
  );
  late final _reports = Reports(widget.db);
  late final _beeper = CardBeeper(_connection.events);
  late final _simulator = Simulator(connection: _connection, students: widget.students, rules: widget.rules);
  late final _rateSync = RateSync(connection: _connection, rules: widget.rules);
  late final _autoConnect = AutoConnect(connection: _connection, auth: widget.auth);

  /// The admin opened the display screen from the sidebar; unlocking it returns to admin.
  bool _adminOnDisplay = false;

  @override
  void initState() {
    super.initState();
    _beeper; // start listening for card taps right away
    _rateSync; // and keep the machine's points rate in step
    _autoConnect; // and connect to the machine whenever someone is signed in
  }

  @override
  void dispose() {
    _autoConnect.dispose();
    _rateSync.dispose();
    _simulator.dispose();
    _beeper.dispose();
    _recorder.dispose();
    _session.dispose();
    _connection.dispose();
    widget.officerData.dispose();
    widget.auth.dispose();
    widget.rules.dispose();
    widget.students.dispose();
    widget.db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoEarn',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ListenableBuilder(
        listenable: widget.auth,
        // Signing in or out cross-fades between the screens.
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(
            key: ValueKey((widget.auth.current?.role, _adminOnDisplay)),
            child: switch (widget.auth.current?.role) {
          null => LoginScreen(auth: widget.auth),
          Role.admin when _adminOnDisplay => DisplayKiosk(
              auth: widget.auth,
              connection: _connection,
              session: _session,
              students: widget.students,
              reports: _reports,
              simulator: _simulator,
              rules: widget.rules,
              onExit: () => setState(() => _adminOnDisplay = false),
            ),
          Role.admin => AdminShell(
              auth: widget.auth,
              db: widget.db,
              databasePath: widget.databasePath,
              connection: _connection,
              session: _session,
              students: widget.students,
              recorder: _recorder,
              reports: _reports,
              simulator: _simulator,
              rules: widget.rules,
              autoConnect: _autoConnect,
              onOpenDisplay: () => setState(() => _adminOnDisplay = true),
            ),
          Role.display => DisplayKiosk(
              auth: widget.auth,
              connection: _connection,
              session: _session,
              students: widget.students,
              reports: _reports,
              simulator: _simulator,
              rules: widget.rules,
            ),
          Role.officer => OfficerShell(
              auth: widget.auth,
              data: widget.officerData,
              connection: _connection,
            ),
            },
          ),
        ),
      ),
    );
  }
}
