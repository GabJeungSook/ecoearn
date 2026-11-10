import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/csv_export.dart';
import '../data/reports.dart';
import '../data/student.dart';
import '../reports/transaction_table.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';

/// One student's full record: every card tap that processed a bottle, with
/// date, time, weight, points and result. Filter by month and export to CSV.
class StudentRecordScreen extends StatefulWidget {
  const StudentRecordScreen({super.key, required this.student, required this.reports});

  final Student student;
  final Reports reports;

  @override
  State<StudentRecordScreen> createState() => _StudentRecordScreenState();
}

class _StudentRecordScreenState extends State<StudentRecordScreen> {
  List<(int, int)> _months = const [];
  (int, int)? _month; // null = all time
  List<DepositRecord>? _deposits; // newest first

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.student.id!;
    final months = await widget.reports.monthsWithDeposits(studentId: id);
    final month = _month;
    final deposits = await widget.reports.deposits(studentId: id, year: month?.$1, month: month?.$2);
    if (!mounted) return;
    setState(() {
      _months = months;
      _deposits = deposits.reversed.toList();
    });
  }

  String get _periodLabel => _month == null ? 'All time' : '${monthNames[_month!.$2 - 1]} ${_month!.$1}';

  Future<void> _export() async {
    final deposits = _deposits;
    if (deposits == null) return;
    final s = widget.student;
    final period = _month == null ? 'all' : '${_month!.$1}-${_month!.$2.toString().padLeft(2, '0')}';
    final safeName = s.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').toLowerCase();
    final location = await getSaveLocation(
      suggestedName: 'ecoearn-record-${s.studentNo}-$safeName-$period.csv',
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV (Excel)', extensions: ['csv'])],
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';

    String message;
    try {
      await writeCsvFile(path, depositsCsv(deposits.reversed.toList()));
      message = 'Saved ${deposits.length} rows to $path';
    } catch (e) {
      message = 'Could not save the file: $e. If it is open in Excel, close it and try again.';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    final deposits = _deposits;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
            child: Row(children: [
              SquareIconButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: () => Navigator.pop(context)),
              const SizedBox(width: 18),
              InitialsAvatar(name: s.name, size: 52),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('STUDENT RECORD',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: EcoColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(s.name,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  Text(
                    [s.studentNo, if (s.gradeSection.isNotEmpty) s.gradeSection, 'Card ${s.rfidUid ?? 'none'}']
                        .join(' · '),
                    style: const TextStyle(color: EcoColors.muted),
                  ),
                ]),
              ),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: EcoColors.field, borderRadius: BorderRadius.circular(10)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<(int, int)?>(
                    value: _month,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All time')),
                      for (final m in _months)
                        DropdownMenuItem(value: m, child: Text('${monthNames[m.$2 - 1]} ${m.$1}')),
                    ],
                    onChanged: (m) {
                      setState(() => _month = m);
                      _load();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: FilledButton.icon(
                  onPressed: deposits == null || deposits.isEmpty ? null : _export,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export CSV'),
                ),
              ),
            ]),
          ),
          if (deposits == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 26), child: _summary(deposits)),
            const Padding(
              padding: EdgeInsets.fromLTRB(32, 28, 32, 10),
              child: SmallLabel('Every tap and deposit, newest first'),
            ),
            Expanded(
              child: TransactionTable(
                deposits: deposits,
                emptyMessage: _month == null ? '${s.name} has no deposits yet.' : 'No deposits in $_periodLabel.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(List<DepositRecord> deposits) {
    final accepted = deposits.where((d) => d.rejectReason == null).toList();
    final points = accepted.fold(0, (sum, d) => sum + d.points);
    final grams = accepted.fold(0.0, (sum, d) => sum + d.grams);
    final rejected = deposits.length - accepted.length;
    final last = deposits.isEmpty ? null : deposits.first.occurredAt;
    return Row(children: [
      StatCard(
        icon: Icons.stars_rounded,
        highlight: true,
        label: 'Points · $_periodLabel',
        value: '$points',
        detail: _month == null ? 'Balance: ${widget.student.points} points' : 'earned this month',
      ),
      StatCard(
        icon: Icons.recycling,
        color: EcoColors.teal,
        label: 'Bottles accepted',
        value: '${accepted.length}',
        detail: '$rejected rejected',
      ),
      StatCard(
        icon: Icons.scale,
        color: EcoColors.sky,
        label: 'Plastic recycled',
        value: '${(grams / 1000).toStringAsFixed(2)} kg',
        detail: '${grams.toStringAsFixed(0)} g after draining',
      ),
      StatCard(
        icon: Icons.schedule,
        color: EcoColors.amber,
        label: 'Last deposit',
        value: last == null ? '—' : transactionDate(last),
        detail: last == null ? 'No deposits' : transactionTime(last),
      ),
    ]);
  }
}
