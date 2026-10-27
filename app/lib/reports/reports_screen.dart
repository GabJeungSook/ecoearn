import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/csv_export.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../widgets/stat_card.dart';

enum _Export { monthlySummary, monthDeposits, allDeposits }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.reports, required this.students});

  final Reports reports;

  /// Listened to so the report refreshes when new deposits are saved.
  final StudentRepository students;

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
      appBar: AppBar(
        title: const Text('Monthly report'),
        actions: [
          MenuAnchor(
            builder: (context, controller, _) => FilledButton.icon(
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
            ),
            menuChildren: [
              MenuItemButton(
                onPressed: () => _export(_Export.monthlySummary),
                child: const Text('Monthly report (per student)'),
              ),
              MenuItemButton(
                onPressed: () => _export(_Export.monthDeposits),
                child: const Text("This month's deposits (every bottle)"),
              ),
              MenuItemButton(
                onPressed: () => _export(_Export.allDeposits),
                child: const Text('All deposits, all months (test data)'),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: 200,
                  child: Text(
                    '${monthNames[_month - 1]} $_year',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (report == null)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              Row(
                children: [
                  StatCard(
                    icon: Icons.recycling,
                    label: 'Bottles collected',
                    value: '${report.bottles}',
                    detail: '${report.rejected} rejected',
                  ),
                  StatCard(
                    icon: Icons.scale,
                    label: 'Plastic collected',
                    value: '${(report.grams / 1000).toStringAsFixed(2)} kg',
                    detail: '${report.grams.toStringAsFixed(0)} g after draining',
                  ),
                  StatCard(
                    icon: Icons.eco,
                    label: 'Points awarded',
                    value: '${report.points}',
                    detail: 'this month',
                  ),
                  StatCard(
                    icon: Icons.people_outline,
                    label: 'Participating students',
                    value: '${report.students}',
                    detail: 'with at least one deposit',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _table(context, report)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _table(BuildContext context, MonthlyReport report) {
    if (report.rows.isEmpty) {
      return Card(child: Center(child: Text('No deposits in ${report.title}.')));
    }
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('#')),
              DataColumn(label: Text('Student')),
              DataColumn(label: Text('Student ID')),
              DataColumn(label: Text('Grade & section')),
              DataColumn(label: Text('Bottles'), numeric: true),
              DataColumn(label: Text('Grams'), numeric: true),
              DataColumn(label: Text('Points'), numeric: true),
              DataColumn(label: Text('Rejected'), numeric: true),
            ],
            rows: [
              for (final (i, r) in report.rows.indexed)
                DataRow(cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(r.name, style: r.isRegistered ? null : TextStyle(color: colors.error))),
                  DataCell(Text(r.studentNo ?? '—')),
                  DataCell(Text(r.gradeSection)),
                  DataCell(Text('${r.bottles}')),
                  DataCell(Text(r.grams.toStringAsFixed(1))),
                  DataCell(Text('${r.points}')),
                  DataCell(Text('${r.rejected}')),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
