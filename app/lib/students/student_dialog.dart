import 'dart:async';

import 'package:flutter/material.dart';

import '../data/student.dart';
import '../data/student_repository.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';

/// Add or edit a student. The card can be typed in or read by tapping it on
/// the machine's RFID reader.
class StudentDialog extends StatefulWidget {
  const StudentDialog({
    super.key,
    this.student,
    required this.students,
    required this.connection,
  });

  /// Null to add a new student.
  final Student? student;
  final StudentRepository students;
  final SerialConnection connection;

  @override
  State<StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<StudentDialog> {
  static const _scanTimeout = Duration(seconds: 30);

  late final _studentNo = TextEditingController(text: widget.student?.studentNo);
  late final _name = TextEditingController(text: widget.student?.name);
  late final _gradeSection = TextEditingController(text: widget.student?.gradeSection);
  late final _uid = TextEditingController(text: widget.student?.rfidUid);

  StreamSubscription<DeviceEvent>? _scan;
  Timer? _scanTimer;
  String? _error;
  bool _saving = false;

  bool get _scanning => _scan != null;

  // Register mode makes the ESP32 report the next tap as a ScanEvent instead of
  // starting a deposit; it leaves register mode after one card or 30 seconds.
  void _startScan() {
    if (!widget.connection.send('register')) {
      setState(() => _error = 'Could not talk to the ESP32. Check the connection on the Live screen.');
      return;
    }
    _scan = widget.connection.events.listen((event) {
      if (event is ScanEvent) {
        _uid.text = event.uid;
        _stopScan(cardRead: true);
      }
    });
    _scanTimer = Timer(_scanTimeout, () {
      _stopScan();
      setState(() => _error = 'No card was tapped within ${_scanTimeout.inSeconds} seconds.');
    });
    setState(() => _error = null);
  }

  void _stopScan({bool cardRead = false}) {
    if (_scanning && !cardRead) widget.connection.send('cancel');
    _scan?.cancel();
    _scan = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final uidText = _uid.text.trim();
    final uid = Student.normalizeUid(uidText);
    // MFRC522 UIDs are 4, 7 or 10 bytes = 8, 14 or 20 hex digits.
    if (uidText.isNotEmpty && (uid == null || ![8, 14, 20].contains(uid.length))) {
      setState(() => _error = 'Card UID should look like A3F29B11. Tap "Scan card" to read it.');
      return;
    }

    setState(() => _saving = true);
    final error = await widget.students.save(Student(
      id: widget.student?.id,
      studentNo: _studentNo.text,
      name: _name.text,
      gradeSection: _gradeSection.text,
      rfidUid: uid,
    ));
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    if (_scanning) widget.connection.send('cancel');
    _scan?.cancel();
    _scanTimer?.cancel();
    _studentNo.dispose();
    _name.dispose();
    _gradeSection.dispose();
    _uid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.connection.isConnected;
    final editing = widget.student != null;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      title: Row(children: [
        IconBadge(icon: editing ? Icons.edit_outlined : Icons.person_add_alt_1_outlined, color: EcoColors.emerald),
        const SizedBox(width: 14),
        Text(editing ? 'Edit student' : 'Add student',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Student ID number',
              required: true,
              child: TextField(
                controller: _studentNo,
                autofocus: !editing,
                decoration: const InputDecoration(
                  hintText: 'e.g. 2024-0001',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
              ),
            ),
            LabeledField(
              label: 'Full name',
              required: true,
              child: TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Juan Dela Cruz',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
              ),
            ),
            LabeledField(
              label: 'Grade & section',
              child: TextField(
                controller: _gradeSection,
                decoration: const InputDecoration(
                  hintText: 'e.g. 12 - STEM A',
                  prefixIcon: Icon(Icons.school_outlined, size: 20),
                ),
              ),
            ),
            LabeledField(
              label: 'RFID card',
              helper: _scanning
                  ? "Tap the card on the machine's reader now…"
                  : connected
                      ? 'Tap "Scan card" and hold the card on the reader, or type the UID. Leave empty if no card yet.'
                      : 'Connect to the machine on the Live screen to scan cards, or type the UID.',
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _uid,
                    decoration: const InputDecoration(
                      hintText: 'e.g. A3F29B11',
                      prefixIcon: Icon(Icons.contactless_outlined, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: _scanning
                      ? OutlinedButton.icon(
                          onPressed: () => _stopScan(),
                          icon: const SizedBox.square(
                              dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          label: const Text('Cancel'),
                        )
                      : OutlinedButton.icon(
                          onPressed: connected ? _startScan : null,
                          icon: const Icon(Icons.contactless, size: 18),
                          label: const Text('Scan card'),
                        ),
                ),
              ]),
            ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EcoColors.coral.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: EcoColors.coral, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: EcoColors.coral))),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save changes' : 'Add student'),
        ),
      ],
    );
  }
}
