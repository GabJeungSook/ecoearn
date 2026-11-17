import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/csv_export.dart';
import '../data/fees.dart';
import '../data/payments.dart';
import '../data/student.dart';
import '../data/student_repository.dart';
import '../reports/transaction_table.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';

/// Officers: pay students' fees with their points, see every payment, void a mistake.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    required this.payments,
    required this.fees,
    required this.students,
    required this.officerName,
  });

  final PaymentBook payments;
  final FeeBook fees;
  final StudentRepository students;

  /// Recorded as who processed (or voided) a payment.
  final String officerName;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  static const _flex = [3, 4, 3, 2, 2, 2, 3];
  String _query = '';

  bool _matches(Payment p) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty ||
        p.studentName.toLowerCase().contains(q) ||
        p.studentNo.toLowerCase().contains(q) ||
        p.feeName.toLowerCase().contains(q);
  }

  Future<void> _newPayment() => showDialog<void>(
        context: context,
        builder: (_) => _PayDialog(
          payments: widget.payments,
          fees: widget.fees,
          students: widget.students,
          officerName: widget.officerName,
        ),
      );

  Future<void> _export() async {
    final location = await getSaveLocation(
      suggestedName: 'ecoearn-payments.csv',
      acceptedTypeGroups: const [XTypeGroup(label: 'CSV (Excel)', extensions: ['csv'])],
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.csv')) path = '$path.csv';
    String message;
    try {
      await writeCsvFile(path, paymentsCsv(widget.payments.payments.reversed.toList()));
      message = 'Saved ${widget.payments.payments.length} payments to $path';
    } catch (e) {
      message = 'Could not save the file: $e. If it is open in Excel, close it and try again.';
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.payments, widget.fees, widget.students]),
        builder: (context, _) {
          final all = widget.payments.payments;
          final shown = all.where(_matches).toList();
          final paid = all.where((p) => !p.voided).toList();
          final now = DateTime.now();
          final thisMonth = paid.where((p) => p.paidAt.year == now.year && p.paidAt.month == now.month);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                overline: 'Fees paid with points',
                title: 'Payments',
                actions: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 20),
                        hintText: 'Search student or fee',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  SquareIconButton(
                    icon: Icons.download,
                    tooltip: 'Export payments (CSV)',
                    onPressed: all.isEmpty ? null : _export,
                  ),
                  SizedBox(
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: widget.fees.activeFees.isEmpty ? null : _newPayment,
                      icon: const Icon(Icons.point_of_sale, size: 18),
                      label: const Text('Pay a fee'),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Row(children: [
                  StatCard(
                    icon: Icons.point_of_sale,
                    highlight: true,
                    label: 'Fees paid this month',
                    value: '${thisMonth.length}',
                    detail: '${paid.length} in total',
                  ),
                  StatCard(
                    icon: Icons.stars_rounded,
                    color: EcoColors.amber,
                    label: 'Points used this month',
                    value: '${thisMonth.fold(0, (s, p) => s + p.points)}',
                    detail: '${paid.fold(0, (s, p) => s + p.points)} in total',
                  ),
                  StatCard(
                    icon: Icons.payments_outlined,
                    color: EcoColors.teal,
                    label: 'Pesos settled this month',
                    value: pesos(thisMonth.fold(0.0, (s, p) => s + p.amount)),
                    detail: '${pesos(paid.fold(0.0, (s, p) => s + p.amount))} in total',
                  ),
                  StatCard(
                    icon: Icons.currency_exchange,
                    color: EcoColors.sky,
                    label: 'Peso value of a point',
                    value: pesos(widget.fees.pesosPerPoint),
                    detail: 'change it in Settings',
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              if (widget.fees.activeFees.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(32, 0, 32, 12),
                  child: Text('Add the fees students can pay with points in Settings first.',
                      style: TextStyle(color: EcoColors.amber, fontWeight: FontWeight.w600)),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: ColumnHeadings(
                  labels: ['Date', 'Student', 'Fee', 'Amount', 'Points', 'Status', 'Processed by'],
                  flex: _flex,
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? EmptyState(
                        icon: Icons.point_of_sale,
                        message: all.isEmpty ? 'No fees paid with points yet.' : 'No payments match "$_query".',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _row(shown[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(Payment p) {
    final cells = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(transactionDate(p.paidAt), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(transactionTime(p.paidAt), style: const TextStyle(color: EcoColors.muted, fontSize: 12)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.studentName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(p.studentNo, style: const TextStyle(color: EcoColors.muted, fontSize: 12)),
      ]),
      Text(p.feeName, overflow: TextOverflow.ellipsis),
      Text(pesos(p.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('−${p.points}', style: TextStyle(fontWeight: FontWeight.w700, color: p.voided ? EcoColors.muted : EcoColors.coral)),
      Align(alignment: Alignment.centerLeft, child: _StatusPill(voided: p.voided)),
      Text(p.processedBy.isEmpty ? '—' : p.processedBy, overflow: TextOverflow.ellipsis),
    ];
    return RowCard(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _PaymentDetail(payment: p, payments: widget.payments, officerName: widget.officerName),
      ),
      child: Row(children: [for (var c = 0; c < cells.length; c++) Expanded(flex: _flex[c], child: cells[c])]),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.voided});

  final bool voided;

  @override
  Widget build(BuildContext context) {
    final color = voided ? EcoColors.muted : EcoColors.emerald;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        voided ? 'Voided' : 'Paid',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: voided ? EcoColors.muted : EcoColors.forest),
      ),
    );
  }
}

/// Pick a student and a fee; it is paid only if the student has every point it needs.
class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.payments, required this.fees, required this.students, required this.officerName});

  final PaymentBook payments;
  final FeeBook fees;
  final StudentRepository students;
  final String officerName;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  Student? _student;
  Fee? _fee;
  String? _error;
  bool _saving = false;

  Future<void> _pay() async {
    final student = _student, fee = _fee;
    if (student == null || fee == null) return;
    setState(() => _saving = true);
    final error = await widget.payments.pay(
      student: student,
      fee: fee,
      book: widget.fees,
      processedBy: widget.officerName,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Paid ${fee.name} (${pesos(fee.amount)}) for ${student.name} with '
            '${widget.fees.pointsFor(fee.amount)} points.'),
      ));
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = _student == null ? null : widget.students.students.where((s) => s.id == _student!.id).firstOrNull;
    final fee = _fee;
    final needed = fee == null ? null : widget.fees.pointsFor(fee.amount);
    final enough = student != null && needed != null && student.points >= needed;

    return AlertDialog(
      title: const Row(children: [
        IconBadge(icon: Icons.point_of_sale, color: EcoColors.emerald),
        SizedBox(width: 14),
        Text('Pay a fee with points', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(
            label: 'Student',
            required: true,
            child: Autocomplete<Student>(
              displayStringForOption: (s) => '${s.name} · ${s.studentNo}',
              optionsBuilder: (value) {
                final q = value.text.trim().toLowerCase();
                return widget.students.students.where((s) =>
                    q.isEmpty ||
                    s.name.toLowerCase().contains(q) ||
                    s.studentNo.toLowerCase().contains(q) ||
                    (s.rfidUid?.toLowerCase().contains(q) ?? false));
              },
              onSelected: (s) => setState(() {
                _student = s;
                _error = null;
              }),
              fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a name or student ID',
                  prefixIcon: Icon(Icons.person_search_outlined, size: 20),
                ),
                onChanged: (_) {
                  if (_student != null) setState(() => _student = null);
                },
              ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260, maxWidth: 480),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        for (final s in options)
                          ListTile(
                            dense: true,
                            leading: InitialsAvatar(name: s.name, size: 32),
                            title: Text(s.name),
                            subtitle: Text([s.studentNo, s.gradeSection].where((t) => t.isNotEmpty).join(' · ')),
                            trailing: Text('${s.points} pts', style: const TextStyle(fontWeight: FontWeight.w700)),
                            onTap: () => onSelected(s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          LabeledField(
            label: 'Fee',
            required: true,
            child: DropdownButtonFormField<Fee>(
              initialValue: _fee,
              hint: const Text('Choose the fee'),
              borderRadius: BorderRadius.circular(12),
              items: [
                for (final f in widget.fees.activeFees)
                  DropdownMenuItem(
                    value: f,
                    child: Text('${f.name} · ${pesos(f.amount)} · ${widget.fees.pointsFor(f.amount)} points'),
                  ),
              ],
              onChanged: (f) => setState(() {
                _fee = f;
                _error = null;
              }),
            ),
          ),
          if (student != null && needed != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: enough ? EcoColors.mint : EcoColors.coral.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _line('Balance', '${student.points} points'),
                _line('${fee!.name} (${pesos(fee.amount)})', '−$needed points'),
                const Divider(height: 18),
                if (enough)
                  _line('Balance after paying', '${student.points - needed} points', bold: true)
                else
                  Text(
                    'Not enough points: needs ${needed - student.points} more. Fees can only be paid in full.',
                    style: const TextStyle(color: EcoColors.coral, fontWeight: FontWeight.w600),
                  ),
              ]),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: EcoColors.coral)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: enough && !_saving ? _pay : null,
          child: Text(needed == null ? 'Pay' : 'Pay with $needed points'),
        ),
      ],
    );
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

class _PaymentDetail extends StatefulWidget {
  const _PaymentDetail({required this.payment, required this.payments, required this.officerName});

  final Payment payment;
  final PaymentBook payments;
  final String officerName;

  @override
  State<_PaymentDetail> createState() => _PaymentDetailState();
}

class _PaymentDetailState extends State<_PaymentDetail> {
  final _reason = TextEditingController();
  bool _voiding = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _void() async {
    final error = await widget.payments.voidPayment(widget.payment, reason: _reason.text, voidedBy: widget.officerName);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment voided. ${widget.payment.points} points returned to ${widget.payment.studentName}.'),
      ));
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    Widget detail(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(color: EcoColors.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return AlertDialog(
      title: Text('${p.feeName} · ${pesos(p.amount)}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          detail('Student', '${p.studentName} (${p.studentNo})'),
          detail('Points used', '${p.points} at ${pesos(p.pesosPerPoint)} per point'),
          detail('Paid', '${transactionDate(p.paidAt)}, ${transactionTime(p.paidAt)}'),
          detail('Processed by', p.processedBy.isEmpty ? '—' : p.processedBy),
          if (p.voided) ...[
            detail('Voided', '${transactionDate(p.voidedAt!)}, ${transactionTime(p.voidedAt!)}'
                '${(p.voidedBy ?? '').isEmpty ? '' : ' by ${p.voidedBy}'}'),
            detail('Reason', p.voidReason ?? '—'),
          ] else if (_voiding) ...[
            const SizedBox(height: 6),
            LabeledField(
              label: 'Why is it voided?',
              required: true,
              helper: 'The ${p.points} points go back to the student. The payment stays in the record as voided.',
              child: TextField(
                controller: _reason,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'e.g. Wrong fee chosen'),
              ),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: EcoColors.coral)),
          ],
        ]),
      ),
      actions: [
        if (!p.voided && !_voiding)
          TextButton(
            onPressed: () => setState(() => _voiding = true),
            child: const Text('Void payment', style: TextStyle(color: EcoColors.coral)),
          ),
        if (_voiding)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: EcoColors.coral),
            onPressed: _void,
            child: const Text('Void and return points'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
