import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/csv_export.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';

enum _Export { monthlySummary, monthDeposits, allDeposits }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.reports,
    required this.students,
    this.subtitle,
    this.onExportForOfficers,
  });

  final Reports reports;

  /// Listened to so the report refreshes when new deposits are saved.
  final StudentRepository students;

  /// Shown under the title, e.g. which data file an officer is viewing.
  final String? subtitle;

  /// Admin only: adds "Data file for officers" to the export menu.
  final VoidCallback? onExportForOfficers;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late int _year;
  late int _month;
  MonthlyReport? _report;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    widget.students.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.students.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final report = await widget.reports.monthly(_year, _month);
    if (mounted && report.year == _year && report.month == _month) {
      setState(() => _report = report);
    }
  }

  void _shiftMonth(int delta) {
    final first = DateTime(_year, _month + delta);
    setState(() {
      _year = first.year;
      _month = first.month;
      _report = null;
    });
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  Future<void> _export(_Export kind) async {
    final monthTag = '$_year-${_month.toString().padLeft(2, '0')}';
    final suggestedName = switch (kind) {
      _Export.monthlySummary => 'ecoearn-report-$monthTag.csv',
      _Export.monthDeposits => 'ecoearn-deposits-$monthTag.csv',
      _Export.allDeposits => 'ecoearn-deposits-all.csv',
    };
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV (Excel)', extensions: ['csv'])],
    );
    if (location == null) return; // cancelled

    var path = location.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';

    final rows = switch (kind) {
      _Export.monthlySummary => monthlyReportCsv(await widget.reports.monthly(_year, _month)),
      _Export.monthDeposits => depositsCsv(await widget.reports.deposits(year: _year, month: _month)),
      _Export.allDeposits => depositsCsv(await widget.reports.deposits()),
    };

    String message;
    try {
      await writeCsvFile(path, rows);
      message = 'Saved ${rows.length - 1} rows to $path';
    } catch (e) {
      message = 'Could not save the file: $e. If it is open in Excel, close it and try again.';
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            overline: widget.subtitle ?? 'Monthly report',
            title: '${monthNames[_month - 1]} $_year',
            actions: [
              SquareIconButton(icon: Icons.chevron_left, tooltip: 'Previous month', onPressed: () => _shiftMonth(-1)),
              SquareIconButton(
                icon: Icons.chevron_right,
                tooltip: 'Next month',
                onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
              ),
              MenuAnchor(
                builder: (context, controller, _) => SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Export'),
                  ),
                ),
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => _export(_Export.monthlySummary),
                    child: const Text('Monthly report (per student) · CSV'),
                  ),
                  MenuItemButton(
                    onPressed: () => _export(_Export.monthDeposits),
                    child: const Text("This month's deposits (every bottle) · CSV"),
                  ),
                  MenuItemButton(
                    onPressed: () => _export(_Export.allDeposits),
                    child: const Text('All deposits, all months (test data) · CSV'),
                  ),
                  if (widget.onExportForOfficers != null) ...[
                    const Divider(),
                    MenuItemButton(
                      onPressed: widget.onExportForOfficers,
                      leadingIcon: const Icon(Icons.save_alt),
                      child: const Text('Data file for officers (.ecoearn)'),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (report == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Row(
                children: [
                  StatCard(
                    icon: Icons.recycling,
                    highlight: true,
                    label: 'Bottles collected',
                    value: '${report.bottles}',
                    detail: '${report.rejected} rejected',
                  ),
                  StatCard(
                    icon: Icons.scale,
                    color: EcoColors.sky,
                    label: 'Plastic collected',
                    value: '${(report.grams / 1000).toStringAsFixed(2)} kg',
                    detail: '${report.grams.toStringAsFixed(0)} g after draining',
                  ),
                  StatCard(
                    icon: Icons.eco,
                    color: EcoColors.amber,
                    label: 'Points awarded',
                    value: '${report.points}',
                    detail: 'this month',
                  ),
                  StatCard(
                    icon: Icons.people_outline,
                    color: EcoColors.teal,
                    label: 'Participating students',
                    value: '${report.students}',
                    detail: 'with at least one deposit',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Expanded(child: _table(report)),
          ],
        ],
      ),
    );
  }

  static const _flex = [1, 5, 3, 3, 2, 2, 2, 2];

  Widget _table(MonthlyReport report) {
    if (report.rows.isEmpty) {
      return EmptyState(icon: Icons.bar_chart_rounded, message: 'No deposits in ${report.title}.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: ColumnHeadings(
            labels: ['#', 'Student', 'Student ID', 'Grade & section', 'Bottles', 'Grams', 'Points', 'Rejected'],
            flex: _flex,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            itemCount: report.rows.length,
            itemBuilder: (context, i) {
              final r = report.rows[i];
              final cells = <Widget>[
                Text('${i + 1}', style: const TextStyle(color: EcoColors.muted)),
                Text(r.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: r.isRegistered ? null : EcoColors.coral,
                    )),
                Text(r.studentNo ?? '—'),
                Text(r.gradeSection, overflow: TextOverflow.ellipsis),
                Text('${r.bottles}'),
                Text(r.grams.toStringAsFixed(1)),
                Text('${r.points}', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${r.rejected}', style: TextStyle(color: r.rejected > 0 ? EcoColors.coral : EcoColors.muted)),
              ];
              return RowCard(
                child: Row(children: [
                  for (var c = 0; c < cells.length; c++) Expanded(flex: _flex[c], child: cells[c]),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }
}
