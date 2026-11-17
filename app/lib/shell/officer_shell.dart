import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../data/fees.dart';
import '../data/officer_data.dart';
import '../payments/payments_screen.dart';
import '../serial/serial_connection.dart';
import '../reports/reports_screen.dart';
import '../students/students_screen.dart';
import '../widgets/stat_card.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import '../widgets/page_parts.dart';
import '../settings/fee_settings.dart';
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

    final result = await widget.data.import(file.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.summary)));
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
          final source = data.exportedAt == null ? '' : 'Newest data exported ${_date(data.exportedAt!)}';

          return Scaffold(
            body: Row(
              children: [
                AppSidebar(
                  auth: widget.auth,
                  selectedIndex: _screen,
                  onSelected: data.hasData ? (i) => setState(() => _screen = i) : null,
                  action: SquareIconButton(
                    icon: Icons.file_open_outlined,
                    tooltip: 'Import a data file (adds it to the data already here)',
                    onPressed: _import,
                    primary: true,
                  ),
                  items: const [
                    SidebarItem(Icons.bar_chart_rounded, 'Reports'),
                    SidebarItem(Icons.people_outline, 'Students'),
                    SidebarItem(Icons.point_of_sale, 'Payments'),
                    SidebarItem(Icons.tune_rounded, 'Settings'),
                  ],
                ),
                Expanded(
                  child: students == null || reports == null || data.fees == null || data.payments == null
                      ? _noData(context)
                      : ScreenSwitcher(
                          // Each import rebuilds the screens, so they show the merged data.
                          key: ValueKey(data.revision),
                          index: _screen,
                          children: [
                            ReportsScreen(reports: reports, students: students, subtitle: source),
                            StudentsScreen(
                              students: students,
                              reports: reports,
                              connection: widget.connection,
                              footer: source,
                              readOnly: true,
                              payments: data.payments,
                            ),
                            PaymentsScreen(
                              payments: data.payments!,
                              fees: data.fees!,
                              students: students,
                              officerName: widget.auth.current?.displayName ?? '',
                            ),
                            _OfficerSettings(fees: data.fees!, changedBy: widget.auth.current?.displayName ?? ''),
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
            const Text('Plug in the flash drive from the admin, then open the .ecoearn file on it.\n'
                'Each new file is added to the data already here.',
                textAlign: TextAlign.center),
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

class _OfficerSettings extends StatelessWidget {
  const _OfficerSettings({required this.fees, required this.changedBy});

  final FeeBook fees;
  final String changedBy;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const PageHeader(overline: 'Paying fees with points', title: 'Settings'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: FeeSettings(
                book: fees,
                changedBy: changedBy,
                note: 'Changes here stay on this computer. When the admin changes a fee or the peso value, '
                    'the newer change wins at the next import.',
              ),
            ),
          ],
        ),
      );
}
