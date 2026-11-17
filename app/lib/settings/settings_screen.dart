import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_service.dart';
import '../data/fees.dart';
import '../data/point_rules.dart';
import '../data/reports.dart';
import '../serial/serial_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';
import 'fee_settings.dart';

/// Admin settings: the points rate, with a history of changes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.rules, required this.fees, required this.auth, required this.connection});

  final PointRules rules;
  final FeeBook fees;
  final AuthService auth;
  final SerialConnection connection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _grams = TextEditingController(text: '${widget.rules.gramsPerPoint}');
  String? _error;
  bool _saving = false;

  int? get _entered => int.tryParse(_grams.text.trim());

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final grams = _entered;
    if (grams == null) {
      setState(() => _error = 'Enter a whole number of grams, e.g. 10.');
      return;
    }
    final before = widget.rules.gramsPerPoint;
    if (grams == before) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change the points rate?'),
        content: Text(
          'From now on: 1 point for every $grams g (was $before g).\n\n'
          'Deposits already made keep the points they earned.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Change rate')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    final error = await widget.rules.setGramsPerPoint(grams, changedBy: widget.auth.current?.displayName ?? '');
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.connection.isConnected
            ? 'Saved. The machine now gives 1 point for every $grams g.'
            : 'Saved. The machine is updated the next time it connects.'),
      ));
    }
  }

  static String _date(DateTime t) =>
      '${monthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year} · '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.rules, widget.connection]),
        builder: (context, _) {
          final rules = widget.rules;
          final history = rules.history;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const PageHeader(overline: 'System', title: 'Settings'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FadeSlideIn(delay: const Duration(milliseconds: 80), child: _rateCard(rules)),
                  const SizedBox(height: 28),
                  const SmallLabel('Rate history'),
                  const SizedBox(height: 10),
                  if (history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Not changed yet. The rate has been 1 point per 10 g since the start.',
                          style: TextStyle(color: EcoColors.muted)),
                    )
                  else
                    for (final (i, change) in history.indexed)
                      RowCard(
                        child: Row(children: [
                          IconBadge(icon: Icons.tune, color: i == 0 ? EcoColors.emerald : EcoColors.muted, size: 32),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '1 point for every ${change.gramsPerPoint} g',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (i == 0)
                            Container(
                              margin: const EdgeInsets.only(right: 14),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: EcoColors.mint, borderRadius: BorderRadius.circular(6)),
                              child: const Text('CURRENT',
                                  style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: EcoColors.forest)),
                            ),
                          Text(
                            '${_date(change.changedAt)}${change.changedBy.isEmpty ? '' : ' · ${change.changedBy}'}',
                            style: const TextStyle(color: EcoColors.muted, fontSize: 13),
                          ),
                        ]),
                      ),
                  const SizedBox(height: 36),
                  const SmallLabel('Paying fees with points'),
                  const SizedBox(height: 10),
                  FeeSettings(
                    book: widget.fees,
                    changedBy: widget.auth.current?.displayName ?? '',
                    note: 'Fees and the peso value go to the officers with the next data file '
                        '(Reports → Export). Officers pay the fees on their computer.',
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rateCard(PointRules rules) {
    final entered = _entered;
    final changed = entered != null && entered != rules.gramsPerPoint;
    final example = entered == null || entered < 1 ? null : 25 ~/ entered;
    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EcoColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          IconBadge(icon: Icons.stars_rounded, color: EcoColors.emerald),
          SizedBox(width: 14),
          Text('Point system', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Text('1 point for every', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _grams,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(suffixText: 'g', isDense: true),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 12),
          const Text('of plastic', style: TextStyle(fontSize: 16)),
          const Spacer(),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: changed && !_saving ? _save : null,
              child: const Text('Save'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          example == null
              ? 'Decimals are dropped.'
              : 'Example: a 25 g bottle earns $example ${example == 1 ? 'point' : 'points'}. Decimals are dropped.',
          style: const TextStyle(color: EcoColors.muted, fontSize: 13),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: EcoColors.coral)),
        ],
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 14),
        const _Note(icon: Icons.history_rounded, text: 'Changing the rate only affects new deposits. Past deposits keep their points.'),
        const SizedBox(height: 8),
        _Note(
          icon: widget.connection.isConnected ? Icons.check_circle_outline : Icons.info_outline,
          text: widget.connection.isConnected
              ? 'The machine is connected and uses this rate.'
              : 'The machine gets the new rate the next time it connects, and keeps it even without the laptop.',
        ),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: EcoColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: EcoColors.muted, fontSize: 13))),
      ]);
}
