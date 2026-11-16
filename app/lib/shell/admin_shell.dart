import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/accounts_screen.dart';
import '../auth/auth_service.dart';
import '../data/deposit_recorder.dart';
import '../data/officer_data.dart';
import '../data/point_rules.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../live/live_screen.dart';
import '../live/live_session.dart';
import '../reports/reports_screen.dart';
import '../serial/auto_connect.dart';
import '../serial/serial_connection.dart';
import '../serial/simulator.dart';
import '../settings/settings_screen.dart';
import '../students/students_screen.dart';
import '../widgets/motion.dart';
import 'app_sidebar.dart';
import 'window_controls.dart';

/// Everything: Live, Students, Reports, Accounts.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.auth,
    required this.db,
    required this.databasePath,
    required this.connection,
    required this.session,
    required this.students,
    required this.recorder,
    required this.reports,
    required this.simulator,
    required this.rules,
    required this.autoConnect,
    required this.onOpenDisplay,
  });

  final AuthService auth;
  final Database db;
  final String databasePath;
  final SerialConnection connection;
  final Simulator simulator;
  final PointRules rules;
  final AutoConnect autoConnect;

  /// Switches this window to the student-facing display screen.
  final VoidCallback onOpenDisplay;
  final LiveSession session;
  final StudentRepository students;
  final DepositRecorder recorder;
  final Reports reports;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _screen = 0;

  Future<void> _exportForOfficers() async {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final location = await getSaveLocation(
      suggestedName: 'ecoearn-data-$date.${OfficerDataFile.extension}',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'EcoEarn data file', extensions: [OfficerDataFile.extension]),
      ],
    );
    if (location == null) return;

    var path = location.path;
    if (!path.toLowerCase().endsWith('.${OfficerDataFile.extension}')) path = '$path.${OfficerDataFile.extension}';

    String message;
    try {
      await OfficerDataFile.export(widget.db, path);
      message = 'Saved $path. Copy it to a flash drive and import it in the officer account.';
    } catch (e) {
      message = 'Could not save the data file: $e';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenShortcut(
      child: Scaffold(
        body: Row(
          children: [
            AppSidebar(
              auth: widget.auth,
              selectedIndex: _screen,
              onSelected: (i) => setState(() => _screen = i),
              onOpenDisplay: widget.onOpenDisplay,
              items: const [
                SidebarItem(Icons.sensors, 'Live'),
                SidebarItem(Icons.people_outline, 'Students'),
                SidebarItem(Icons.bar_chart_rounded, 'Reports'),
                SidebarItem(Icons.manage_accounts_outlined, 'Accounts'),
                SidebarItem(Icons.tune_rounded, 'Settings'),
              ],
            ),
            Expanded(
              // ScreenSwitcher keeps each screen's state (port list, search) when switching.
              child: ScreenSwitcher(
                index: _screen,
                children: [
                  LiveScreen(
                    connection: widget.connection,
                    session: widget.session,
                    students: widget.students,
                    recorder: widget.recorder,
                    simulator: widget.simulator,
                    autoConnect: widget.autoConnect,
                  ),
                  StudentsScreen(
                    students: widget.students,
                    reports: widget.reports,
                    connection: widget.connection,
                    footer: 'Database: ${widget.databasePath}',
                  ),
                  ReportsScreen(
                    reports: widget.reports,
                    students: widget.students,
                    onExportForOfficers: _exportForOfficers,
                  ),
                  AccountsScreen(auth: widget.auth),
                  SettingsScreen(rules: widget.rules, auth: widget.auth, connection: widget.connection),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
