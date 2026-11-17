import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fees.dart';
import '../data/reports.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';

/// Fees students can pay with points, and what one point is worth in pesos.
/// Used on both the admin's and the officers' Settings screens.
class FeeSettings extends StatelessWidget {
  const FeeSettings({super.key, required this.book, required this.changedBy, this.note});

  final FeeBook book;

  /// Name recorded with a peso rate change.
  final String changedBy;

  /// Explains where changes go (differs for admin and officers).
  final String? note;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: book,
        builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Card(
            icon: Icons.currency_exchange,
            title: 'Peso value of a point',
            child: _RateEditor(book: book, changedBy: changedBy),
          ),
          const SizedBox(height: 16),
          _Card(
            icon: Icons.receipt_long_outlined,
            title: 'Fees payable with points',
            trailing: SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: () => _editFee(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add fee'),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'A fee is paid in full with points, never partly. Points needed = amount ÷ peso value, '
                'rounded up.',
                style: const TextStyle(color: EcoColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (book.fees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No fees yet. Add the fees students may pay with points, e.g. Late fee ₱20.',
                      style: TextStyle(color: EcoColors.muted)),
                )
              else
                for (final fee in book.fees) _feeRow(context, fee),
              if (note != null) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, size: 18, color: EcoColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note!, style: const TextStyle(color: EcoColors.muted, fontSize: 13))),
                ]),
              ],
            ]),
          ),
        ]),
      );

  Widget _feeRow(BuildContext context, Fee fee) => RowCard(
        child: Row(children: [
          IconBadge(icon: Icons.sell_outlined, color: fee.active ? EcoColors.emerald : EcoColors.muted, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              fee.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: fee.active ? null : EcoColors.muted,
                decoration: fee.active ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          SizedBox(width: 110, child: Text(pesos(fee.amount), style: const TextStyle(fontWeight: FontWeight.w700))),
          SizedBox(
            width: 110,
            child: Text('${book.pointsFor(fee.amount)} points', style: const TextStyle(color: EcoColors.muted)),
          ),
          if (!fee.active)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: EcoColors.field, borderRadius: BorderRadius.circular(6)),
              child: const Text('ARCHIVED',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: EcoColors.muted)),
            ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _editFee(context, fee),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: fee.active ? 'Archive (no longer payable)' : 'Make payable again',
            onPressed: () async {
              final error = await book.setActive(fee, !fee.active);
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
              }
            },
            icon: Icon(fee.active ? Icons.archive_outlined : Icons.unarchive_outlined, size: 20),
          ),
        ]),
      );

  Future<void> _editFee(BuildContext context, Fee? fee) =>
      showDialog<void>(context: context, builder: (_) => _FeeDialog(book: book, fee: fee));
}

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child, this.trailing});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: EcoColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconBadge(icon: icon, color: EcoColors.emerald),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ?trailing,
          ]),
          const SizedBox(height: 18),
          child,
        ]),
      );
}

class _RateEditor extends StatefulWidget {
  const _RateEditor({required this.book, required this.changedBy});

  final FeeBook book;
  final String changedBy;

  @override
  State<_RateEditor> createState() => _RateEditorState();
}

class _RateEditorState extends State<_RateEditor> {
  late final _rate = TextEditingController(text: _format(widget.book.pesosPerPoint));
  String? _error;

  static String _format(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double? get _entered => double.tryParse(_rate.text.trim());

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rate = _entered;
    if (rate == null) {
      setState(() => _error = 'Enter a number, e.g. 1 or 0.50.');
      return;
    }
    final before = widget.book.pesosPerPoint;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change the peso value of a point?'),
        content: Text('From now on: 1 point = ${pesos(rate)} (was ${pesos(before)}).\n\n'
            'Fees already paid keep the points they used.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Change')),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await widget.book.setPesosPerPoint(rate, changedBy: widget.changedBy);
    if (mounted) setState(() => _error = error);
  }

  static String _date(DateTime t) => '${monthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year}';

  @override
  Widget build(BuildContext context) {
    final entered = _entered;
    final changed = entered != null && entered != widget.book.pesosPerPoint;
    final last = widget.book.history.firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('1 point =', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _rate,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(prefixText: '₱ ', isDense: true),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
        ),
        const Spacer(),
        SizedBox(height: 44, child: FilledButton(onPressed: changed ? _save : null, child: const Text('Save'))),
      ]),
      const SizedBox(height: 10),
      Text(
        last == null
            ? 'Not changed yet.'
            : 'Last changed ${_date(last.changedAt)}${last.changedBy.isEmpty ? '' : ' by ${last.changedBy}'}.',
        style: const TextStyle(color: EcoColors.muted, fontSize: 13),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: EcoColors.coral)),
      ],
    ]);
  }
}

class _FeeDialog extends StatefulWidget {
  const _FeeDialog({required this.book, this.fee});

  final FeeBook book;
  final Fee? fee;

  @override
  State<_FeeDialog> createState() => _FeeDialogState();
}

class _FeeDialogState extends State<_FeeDialog> {
  late final _name = TextEditingController(text: widget.fee?.name);
  late final _amount = TextEditingController(
      text: widget.fee == null ? '' : widget.fee!.amount.toStringAsFixed(widget.fee!.amount % 1 == 0 ? 0 : 2));
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final fee = widget.fee;
    final error = fee == null
        ? await widget.book.addFee(_name.text, amount)
        : await widget.book.updateFee(fee, _name.text, amount);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim());
    return AlertDialog(
      title: Text(widget.fee == null ? 'Add fee' : 'Edit fee'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LabeledField(
            label: 'Fee name',
            required: true,
            child: TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. Late fee'),
            ),
          ),
          LabeledField(
            label: 'Amount',
            required: true,
            helper: amount == null || amount <= 0
                ? null
                : 'Costs ${widget.book.pointsFor(amount)} points at ${pesos(widget.book.pesosPerPoint)} per point.',
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(prefixText: '₱ ', hintText: '20'),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: EcoColors.coral)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: Text(widget.fee == null ? 'Add fee' : 'Save changes')),
      ],
    );
  }
}
