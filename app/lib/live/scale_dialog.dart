import 'dart:async';

import 'package:flutter/material.dart';

import '../serial/serial_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';

/// Calibrates the load cell from the app: zero the empty scale, then put a
/// known weight on and enter its grams. Sends the firmware's `tare`, `cal` and
/// `weigh` commands and shows the live weight. The machine must be idle (it
/// ignores commands during a deposit).
class ScaleDialog extends StatefulWidget {
  const ScaleDialog({super.key, required this.connection});

  final SerialConnection connection;

  @override
  State<ScaleDialog> createState() => _ScaleDialogState();
}

class _ScaleDialogState extends State<ScaleDialog> {
  static final _weightLine = RegExp(r'^Weight: (-?[\d.]+) g');

  // Known weight preset: ₱20 + 2 × ₱10 + 6 × ₱5 (new coins) ≈ 72 g.
  final _grams = TextEditingController(text: '72');
  late final StreamSubscription<String> _notes;
  late final Timer _poll;

  double? _weight;
  String? _status; // last answer from the machine
  bool _statusIsError = false;
  bool _waiting = false; // a zero or calibration is running

  @override
  void initState() {
    super.initState();
    _notes = widget.connection.notes.listen(_onNote);
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!_waiting) widget.connection.send('weigh');
    });
  }

  @override
  void dispose() {
    _poll.cancel();
    _notes.cancel();
    _grams.dispose();
    super.dispose();
  }

  void _onNote(String note) {
    final weight = _weightLine.firstMatch(note);
    if (weight != null) {
      setState(() => _weight = double.tryParse(weight.group(1)!));
    } else if (note.startsWith('Scale zeroed')) {
      _finish('Zeroed. Now put the known weight on the tip.', error: false);
    } else if (note.startsWith('Calibrated and saved')) {
      _finish('Calibrated and saved on the machine.', error: false);
    } else if (note.startsWith('Calibration failed')) {
      _finish('Not enough weight detected. Zero with the scale empty, then put the weight on the tip.',
          error: true);
    } else if (note.startsWith('Scale not calibrated')) {
      setState(() => _weight = null);
    }
  }

  void _finish(String message, {required bool error}) => setState(() {
        _waiting = false;
        _status = message;
        _statusIsError = error;
      });

  void _send(String command, String busyMessage) {
    if (!widget.connection.send(command)) {
      _finish('The machine is not connected.', error: true);
      return;
    }
    setState(() {
      _waiting = true;
      _status = busyMessage;
      _statusIsError = false;
    });
  }

  void _calibrate() {
    final grams = double.tryParse(_grams.text.trim().replaceAll(',', '.'));
    if (grams == null || grams <= 0) {
      _finish('Enter the known weight in grams, e.g. 72.', error: true);
      return;
    }
    _send('cal ${grams.toStringAsFixed(1)}', 'Calibrating, keep your hands off…');
  }

  @override
  Widget build(BuildContext context) {
    final weight = _weight;
    return AlertDialog(
      title: const Text('Calibrate the scale'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(color: EcoColors.mint, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const Text('Current weight', style: TextStyle(color: EcoColors.forest, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: Motion.fast,
                  child: Text(
                    weight == null ? '—' : '${weight.toStringAsFixed(1)} g',
                    key: ValueKey(weight?.toStringAsFixed(1)),
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: EcoColors.forest),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            const Text(
              'Weights go on the free end of the load cell, over its two screw holes. '
              'Not on the middle: that part bends and reads wrong.',
              style: TextStyle(fontSize: 13, color: EcoColors.muted),
            ),
            const SizedBox(height: 20),
            _Step(
              number: 1,
              title: 'Take everything off the scale',
              action: OutlinedButton(
                onPressed: _waiting ? null : () => _send('tare', 'Zeroing, keep your hands off…'),
                child: const Text('Zero'),
              ),
            ),
            const SizedBox(height: 14),
            _Step(
              number: 2,
              title: 'Put a known weight on the tip',
              subtitle: '₱20 + 2 × ₱10 + 6 × ₱5 (new coins) ≈ 72 g',
              action: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _grams,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(isDense: true, suffixText: ' g'),
                    onSubmitted: (_) => _calibrate(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _waiting ? null : _calibrate, child: const Text('Calibrate')),
              ]),
            ),
            if (_status != null) ...[
              const SizedBox(height: 18),
              Row(children: [
                if (_waiting)
                  const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(
                    _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18,
                    color: _statusIsError ? EcoColors.coral : EcoColors.emerald,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status!,
                    style: TextStyle(color: _statusIsError ? EcoColors.coral : EcoColors.ink),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, this.subtitle, required this.action});

  final int number;
  final String title;
  final String? subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: EcoColors.emerald, shape: BoxShape.circle),
          child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: EcoColors.muted)),
          ]),
        ),
        const SizedBox(width: 12),
        action,
      ]);
}
