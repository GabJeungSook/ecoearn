import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/csv_export.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../students/student_record_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';
import 'transaction_table.dart';

enum _Export { monthlySummary, monthDeposits, allDeposits }

enum _ResultFilter { all, accepted, rejected }

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
  List<DepositRecord>? _deposits; // the month's deposits, newest first

  bool _showTransactions = false;
  String _query = '';
  _ResultFilter _filter = _ResultFilter.all;

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
    final (year, month) = (_year, _month);
    final report = await widget.reports.monthly(year, month);
    final deposits = await widget.reports.deposits(year: year, month: month);
    if (mounted && year == _year && month == _month) {
      setState(() {
        _report = report;
        _deposits = deposits.reversed.toList();
      });
    }
  }

  void _shiftMonth(int delta) {
    final first = DateTime(_year, _month + delta);
    setState(() {
      _year = first.year;
      _month = first.month;
      _report = null;
      _deposits = null;
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
            overline: widget.subtitle ?? (_showTransactions ? 'All transactions' : 'Monthly report'),
            title: '${monthNames[_month - 1]} $_year',
            actions: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.leaderboard_outlined, size: 18), label: Text('Summary')),
                  ButtonSegment(value: true, icon: Icon(Icons.receipt_long_outlined, size: 18), label: Text('Transactions')),
                ],
                selected: {_showTransactions},
                onSelectionChanged: (v) => setState(() => _showTransactions = v.first),
              ),
              const SizedBox(width: 8),
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
            Expanded(child: _showTransactions ? _transactions() : _table(report)),
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

  // ---------- Transactions: every deposit in the month, any student ----------

  List<DepositRecord> get _filteredDeposits {
    final q = _query.trim().toLowerCase();
    return [
      for (final d in _deposits ?? const <DepositRecord>[])
        if ((_filter == _ResultFilter.all ||
                (_filter == _ResultFilter.accepted) == (d.rejectReason == null)) &&
            (q.isEmpty ||
                (d.name?.toLowerCase().contains(q) ?? false) ||
                (d.studentNo?.toLowerCase().contains(q) ?? false) ||
                (d.gradeSection?.toLowerCase().contains(q) ?? false) ||
                d.cardUid.toLowerCase().contains(q)))
          d,
    ];
  }

  void _openRecord(DepositRecord d) {
    final student = widget.students.students.where((s) => s.id == d.studentId).firstOrNull;
    if (student == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StudentRecordScreen(student: student, reports: widget.reports),
    ));
  }

  Widget _transactions() {
    final shown = _filteredDeposits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
          child: Row(children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search name, ID, section, card',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 11),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            for (final (f, label) in const [
              (_ResultFilter.all, 'All'),
              (_ResultFilter.accepted, 'Accepted'),
              (_ResultFilter.rejected, 'Rejected'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
            const Spacer(),
            SmallLabel("${shown.length} of ${_deposits?.length ?? 0} deposits · click a row for the student's record"),
          ]),
        ),
        Expanded(
          child: TransactionTable(
            deposits: shown,
            showStudent: true,
            onStudentTap: _openRecord,
            emptyMessage: (_deposits?.isEmpty ?? true)
                ? 'No deposits in ${monthNames[_month - 1]} $_year.'
                : 'No deposits match.',
          ),
        ),
      ],
    );
  }
}
