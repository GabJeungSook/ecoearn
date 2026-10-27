import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/officer_data.dart';
import '../serial/serial_connection.dart';
import '../reports/reports_screen.dart';
import '../students/students_screen.dart';
import '../widgets/stat_card.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import 'app_sidebar.dart';
import 'window_controls.dart';

/// Read-only view of a data file the admin exported.
class OfficerShell extends StatefulWidget {
  const OfficerShell({
    super.key,
    required this.auth,
    required this.data,
    required this.connection,
  });

  final AuthService auth;
  final OfficerData data;
  final SerialConnection connection;

  @override
  State<OfficerShell> createState() => _OfficerShellState();
}

class _OfficerShellState extends State<OfficerShell> {
  int _screen = 0;

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'EcoEarn data file', extensions: [OfficerDataFile.extension]),
    ]);
    if (file == null) return;

    final error = await widget.data.import(file.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Data imported.')));
    }
  }

  static String _date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return FullScreenShortcut(
      child: ListenableBuilder(
        listenable: widget.data,
        builder: (context, _) {
          final data = widget.data;
          final students = data.students;
          final reports = data.reports;
          final source = data.exportedAt == null ? '' : 'Data exported ${_date(data.exportedAt!)}';

          return Scaffold(
            body: Row(
              children: [
                AppSidebar(
                  auth: widget.auth,
                  selectedIndex: _screen,
                  onSelected: data.hasData ? (i) => setState(() => _screen = i) : null,
                  action: SquareIconButton(
                    icon: Icons.file_open_outlined,
                    tooltip: 'Import data file',
                    onPressed: _import,
                    primary: true,
                  ),
                  items: const [
                    SidebarItem(Icons.bar_chart_rounded, 'Reports'),
                    SidebarItem(Icons.people_outline, 'Students'),
                  ],
                ),
                Expanded(
                  child: students == null || reports == null
                      ? _noData(context)
                      : IndexedStack(
                          // A new import replaces the screens, so they show the new data.
                          key: ValueKey(data.exportedAt),
                          index: _screen,
                          children: [
                            ReportsScreen(reports: reports, students: students, subtitle: source),
                            StudentsScreen(
                              students: students,
                              reports: reports,
                              connection: widget.connection,
                              footer: source,
                              readOnly: true,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _noData(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(icon: Icons.folder_open_outlined, color: EcoColors.emerald, size: 88),
            const SizedBox(height: 16),
            Text('No data imported yet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Insert the SD card or flash drive from the admin, then open the .ecoearn file on it.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import data file'),
            ),
          ],
        ),
      );
}
