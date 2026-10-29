import 'dart:async';

import 'package:flutter/material.dart';

import '../data/student.dart';
import '../data/student_repository.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';

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
    return AlertDialog(
      title: Text(widget.student == null ? 'Add student' : 'Edit student'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _studentNo,
              autofocus: widget.student == null,
              decoration: const InputDecoration(labelText: 'Student ID number *'),
            ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name *'),
            ),
            TextField(
              controller: _gradeSection,
              decoration: const InputDecoration(labelText: 'Grade & section', hintText: 'e.g. 12 - STEM A'),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _uid,
                    decoration: InputDecoration(
                      labelText: 'RFID card UID',
                      helperText: _scanning
                          ? 'Tap the card on the machine\'s reader now…'
                          : connected
                              ? 'Leave empty if the student has no card yet.'
                              : 'Connect to the ESP32 on the Live screen to scan cards.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (_scanning)
                  OutlinedButton.icon(
                    onPressed: () => _stopScan(),
                    icon: const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    label: const Text('Cancel'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: connected ? _startScan : null,
                    icon: const Icon(Icons.contactless),
                    label: const Text('Scan card'),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
