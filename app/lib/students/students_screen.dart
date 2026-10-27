import 'package:flutter/material.dart';

import '../data/student.dart';
import '../data/student_repository.dart';
import '../serial/serial_connection.dart';
import '../widgets/brand.dart';
import 'student_dialog.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({
    super.key,
    required this.students,
    required this.connection,
    required this.footer,
    this.readOnly = false,
  });

  final StudentRepository students;
  final SerialConnection connection;

  /// Shown after the student count, e.g. where the data comes from.
  final String footer;

  /// Officers can look but not add, edit or delete.
  final bool readOnly;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String _query = '';

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
      appBar: AppBar(
        title: const Text('Students'),
        actions: [
          if (!widget.readOnly)
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.person_add),
              label: const Text('Add student'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.students,
        builder: (context, _) {
          final all = widget.students.students;
          final shown = all.where(_matches).toList();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, ID number, section or card',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: shown.isEmpty
                        ? Center(
                            child: Text(all.isEmpty
                                ? (widget.readOnly ? 'No students in this data.' : 'No students yet. Click "Add student" to register one.')
                                : 'No students match "$_query".'),
                          )
                        : ListView.separated(
                            itemCount: shown.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => _row(context, shown[i]),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${all.length} students · ${widget.footer}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, Student s) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: widget.readOnly ? null : () => _edit(s),
      leading: InitialsAvatar(name: s.name),
      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([s.studentNo, if (s.gradeSection.isNotEmpty) s.gradeSection].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.rfidUid != null)
            Chip(avatar: const Icon(Icons.contactless, size: 16), label: Text(s.rfidUid!))
          else
            Text('No card', style: TextStyle(color: colors.outline)),
          const SizedBox(width: 24),
          SizedBox(
            width: 80,
            child: Text('${s.points} pts',
                textAlign: TextAlign.end, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (!widget.readOnly) ...[
            const SizedBox(width: 8),
            IconButton(tooltip: 'Edit', onPressed: () => _edit(s), icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: 'Delete', onPressed: () => _delete(s), icon: const Icon(Icons.delete_outline)),
          ],
        ],
      ),
    );
  }
}
