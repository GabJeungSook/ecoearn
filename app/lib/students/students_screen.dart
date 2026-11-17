import 'package:flutter/material.dart';

import '../data/payments.dart';
import '../data/reports.dart';
import '../data/student.dart';
import '../data/student_repository.dart';
import '../serial/serial_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';
import 'student_dialog.dart';
import 'student_record_screen.dart';

/// Keep in sync with MAX_ITEM_GRAMS in firmware/ecoearn/config.h (scales the deposit bars).
const _maxItemGrams = 80.0;

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({
    super.key,
    required this.students,
    required this.reports,
    required this.connection,
    required this.footer,
    this.readOnly = false,
    this.payments,
  });

  final StudentRepository students;
  final Reports reports;
  final SerialConnection connection;

  /// Shown after the student count, e.g. where the data comes from.
  final String footer;

  /// Officers can look but not add, edit or delete.
  final bool readOnly;

  /// Officers: fees paid with points, so balances show what's left and the record lists payments.
  final PaymentBook? payments;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  static const _flex = [4, 2, 3, 2, 1];

  String _query = '';
  int? _selectedId;

  bool _matches(Student s) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.name.toLowerCase().contains(q) ||
        s.studentNo.toLowerCase().contains(q) ||
        s.gradeSection.toLowerCase().contains(q) ||
        (s.rfidUid?.toLowerCase().contains(q) ?? false);
  }

  Future<void> _edit(Student? student) => showDialog<void>(
        context: context,
        builder: (_) => StudentDialog(
          student: student,
          students: widget.students,
          connection: widget.connection,
        ),
      );

  Future<void> _delete(Student student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${student.name}?'),
        content: const Text('This removes the student from the list.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await widget.students.delete(student);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.students,
        builder: (context, _) {
          final all = widget.students.students;
          final shown = all.where(_matches).toList();
          final selected = shown.where((s) => s.id == _selectedId).firstOrNull ?? shown.firstOrNull;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      overline: '${all.length} students',
                      title: 'Students',
                      actions: [
                        SizedBox(
                          width: 280,
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search, size: 20),
                              hintText: 'Search name, ID, section, card',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                            onChanged: (value) => setState(() => _query = value),
                          ),
                        ),
                        if (!widget.readOnly)
                          SquareIconButton(
                            icon: Icons.add,
                            tooltip: 'Add student',
                            primary: true,
                            onPressed: () => _edit(null),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: ColumnHeadings(
                        labels: ['Name', 'Student ID', 'Grade & section', 'Card', 'Points'],
                        flex: _flex,
                      ),
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? EmptyState(
                              icon: Icons.people_outline,
                              message: all.isEmpty
                                  ? (widget.readOnly
                                      ? 'No students in this data.'
                                      : 'No students yet. Click + to register one.')
                                  : 'No students match "$_query".',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              itemCount: shown.length,
                              itemBuilder: (context, i) => _row(shown[i], selected: shown[i].id == selected?.id),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 20),
                      child: SmallLabel(widget.footer),
                    ),
                  ],
                ),
              ),
              if (selected != null)
                _StudentDetail(
                  // A new key when the student or their points change reloads the summary.
                  key: ValueKey('${selected.id}-${selected.earned}-${selected.spent}'),
                  student: selected,
                  reports: widget.reports,
                  onEdit: widget.readOnly ? null : () => _edit(selected),
                  onDelete: widget.readOnly ? null : () => _delete(selected),
                  onOpenRecord: () => _openRecord(selected),
                  withPayments: widget.payments != null,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRecord(Student student) => Navigator.of(context).push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, _, _) =>
            StudentRecordScreen(student: student, reports: widget.reports, payments: widget.payments),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.03, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ));

  // Click selects; double-click edits (or opens the record when read-only).
  Widget _row(Student s, {required bool selected}) => GestureDetector(
        onDoubleTap: () => widget.readOnly ? _openRecord(s) : _edit(s),
        child: _rowCard(s, selected: selected),
      );

  Widget _rowCard(Student s, {required bool selected}) => RowCard(
        selected: selected,
        onTap: () => setState(() => _selectedId = s.id),
        child: Row(children: [
          Expanded(
            flex: _flex[0],
            child: Row(children: [
              InitialsAvatar(name: s.name, size: 32, color: selected ? Colors.white : EcoColors.emerald),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Expanded(flex: _flex[1], child: Text(s.studentNo)),
          Expanded(flex: _flex[2], child: Text(s.gradeSection, overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: _flex[3],
            child: Text(
              s.rfidUid ?? 'No card',
              style: TextStyle(color: s.rfidUid == null && !selected ? EcoColors.muted : null),
            ),
          ),
          Expanded(
            flex: _flex[4],
            child: Text('${s.points}', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Right-hand panel: the selected student's summary, recent deposits and details.
class _StudentDetail extends StatefulWidget {
  const _StudentDetail({
    super.key,
    required this.student,
    required this.reports,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenRecord,
    required this.withPayments,
  });

  final Student student;

  /// Officers' view: show the balance after fees.
  final bool withPayments;
  final Reports reports;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onOpenRecord;

  @override
  State<_StudentDetail> createState() => _StudentDetailState();
}

class _StudentDetailState extends State<_StudentDetail> {
  late final _summary = widget.reports.studentSummary(widget.student.id!);

  static String _date(DateTime t) =>
      '${monthNames[t.month - 1].substring(0, 3)} ${t.day}, '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = widget.student;
    return Container(
      width: 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: EcoColors.line)),
      ),
      child: FutureBuilder<StudentSummary>(
        future: _summary,
        builder: (context, snapshot) {
          final summary = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            children: [
              Row(children: [
                Expanded(
                  child: Text(s.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                ),
                if (widget.onDelete != null)
                  IconButton(tooltip: 'Delete', onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline, size: 20)),
              ]),
              const SizedBox(height: 4),
              Text(
                widget.withPayments ? '${s.points} points left' : '${s.earned} points earned',
                style: const TextStyle(fontSize: 16, color: EcoColors.emerald, fontWeight: FontWeight.w700),
              ),
              if (widget.withPayments)
                Text('${s.earned} earned · ${s.spent} used for fees',
                    style: const TextStyle(fontSize: 13, color: EcoColors.muted)),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      onPressed: widget.onOpenRecord,
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: const Text('Full record'),
                    ),
                  ),
                ),
                if (widget.onEdit != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit details'),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 28),
              const SmallLabel('Summary'),
              const SizedBox(height: 12),
              if (summary == null)
                const LinearProgressIndicator()
              else ...[
                Row(children: [
                  Expanded(child: RingStat(value: summary.acceptanceRate, label: 'Accepted')),
                  Expanded(child: RingStat(value: summary.monthShare, label: 'Of points this month', color: EcoColors.amber)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _Figure(value: '${summary.bottles}', label: 'Bottles')),
                  Expanded(child: _Figure(value: (summary.grams / 1000).toStringAsFixed(2), label: 'kg plastic')),
                  Expanded(child: _Figure(value: '${summary.monthPoints}', label: 'Points this month')),
                ]),
                const SizedBox(height: 28),
                const SmallLabel('Recent deposits'),
                const SizedBox(height: 8),
                if (summary.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No deposits yet.', style: TextStyle(color: EcoColors.muted)),
                  )
                else
                  for (final d in summary.recent) _DepositBar(record: d, date: _date(d.occurredAt)),
              ],
              const SizedBox(height: 28),
              _Detail(label: 'Student ID', value: s.studentNo),
              _Detail(label: 'Grade & section', value: s.gradeSection.isEmpty ? '—' : s.gradeSection),
              _Detail(label: 'RFID card', value: s.rfidUid ?? 'No card assigned'),
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        SmallLabel(label),
      ]);
}

class _DepositBar extends StatelessWidget {
  const _DepositBar({required this.record, required this.date});

  final DepositRecord record;
  final String date;

  @override
  Widget build(BuildContext context) {
    final rejected = record.rejectReason != null;
    final color = rejected ? EcoColors.coral : EcoColors.emerald;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(date, style: const TextStyle(fontSize: 13))),
          Text(
            rejected ? 'Rejected' : '${record.grams.toStringAsFixed(0)} g · +${record.points}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: rejected ? color : EcoColors.ink),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (record.grams / _maxItemGrams).clamp(0, 1),
            minHeight: 3,
            color: color,
            backgroundColor: EcoColors.field,
          ),
        ),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SmallLabel(label),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
