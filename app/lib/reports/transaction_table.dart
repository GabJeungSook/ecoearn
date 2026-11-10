import 'package:flutter/material.dart';

import '../data/reports.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';

const rejectLabels = {
  'bin_full': 'Bin full',
  'mechanism': 'Machine problem',
  'no_item': 'No bottle',
  'too_heavy': 'Too heavy',
};

String transactionDate(DateTime t) =>
    '${monthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year}';

String transactionTime(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} '
      '${t.hour < 12 ? 'AM' : 'PM'}';
}

/// One row per processed bottle (each one a card tap): when, how heavy, how
/// many points, accepted or why not. [showStudent] adds the student columns,
/// for the all-students view.
class TransactionTable extends StatelessWidget {
  const TransactionTable({
    super.key,
    required this.deposits,
    this.showStudent = false,
    this.onStudentTap,
    this.emptyMessage = 'No deposits yet.',
  });

  /// Newest first.
  final List<DepositRecord> deposits;
  final bool showStudent;

  /// Opens a student's record when their row is clicked (all-students view).
  final void Function(DepositRecord deposit)? onStudentTap;
  final String emptyMessage;

  List<int> get _flex => showStudent ? [3, 2, 4, 2, 2, 2, 2, 3] : [3, 2, 2, 2, 2, 3];

  @override
  Widget build(BuildContext context) {
    if (deposits.isEmpty) return EmptyState(icon: Icons.receipt_long_outlined, message: emptyMessage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ColumnHeadings(
            labels: [
              'Date',
              'Time',
              if (showStudent) ...['Student', 'Student ID'],
              'Weight',
              'Points',
              'Rate',
              'Result',
            ],
            flex: _flex,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            itemCount: deposits.length,
            itemBuilder: (context, i) => _row(deposits[i]),
          ),
        ),
      ],
    );
  }

  Widget _row(DepositRecord d) {
    final rejected = d.rejectReason != null;
    final cells = <Widget>[
      Text(transactionDate(d.occurredAt), style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(transactionTime(d.occurredAt), style: const TextStyle(color: EcoColors.muted)),
      if (showStudent) ...[
        Text(
          d.name ?? 'Unregistered card ${d.cardUid}',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: d.name == null ? EcoColors.coral : null),
        ),
        Text(d.studentNo ?? '—'),
      ],
      Text('${d.grams.toStringAsFixed(d.grams == d.grams.roundToDouble() ? 0 : 1)} g'),
      Text(rejected ? '—' : '+${d.points}',
          style: TextStyle(fontWeight: FontWeight.w700, color: rejected ? EcoColors.muted : EcoColors.emerald)),
      Text(d.gramsPerPoint == null ? '—' : '${d.gramsPerPoint} g/pt',
          style: const TextStyle(color: EcoColors.muted, fontSize: 13)),
      Align(alignment: Alignment.centerLeft, child: _ResultPill(reason: d.rejectReason)),
    ];
    final tap = onStudentTap;
    return RowCard(
      onTap: tap != null && d.studentId != null ? () => tap(d) : null,
      child: Row(children: [
        for (var c = 0; c < cells.length; c++) Expanded(flex: _flex[c], child: cells[c]),
      ]),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    final accepted = reason == null;
    final color = accepted ? EcoColors.emerald : EcoColors.coral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(
        accepted ? 'Accepted' : 'Rejected · ${rejectLabels[reason] ?? reason}',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accepted ? EcoColors.forest : const Color(0xFF9F1239),
        ),
      ),
    );
  }
}
