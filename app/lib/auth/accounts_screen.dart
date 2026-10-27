import 'package:flutter/material.dart';

import 'account.dart';
import 'auth_service.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.auth});

  final AuthService auth;

  Future<void> _edit(BuildContext context, Account? account) =>
      showDialog<void>(context: context, builder: (_) => _AccountDialog(auth: auth, account: account));

  Future<void> _delete(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${account.username}?'),
        content: const Text('They will no longer be able to sign in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await auth.delete(account);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          FilledButton.icon(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.person_add),
            label: const Text('Add account'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              itemCount: auth.accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = auth.accounts[i];
                final isYou = a.id == auth.current?.id;
                return ListTile(
                  onTap: () => _edit(context, a),
                  leading: CircleAvatar(child: Icon(_roleIcon(a.role))),
                  title: Text('${a.displayName}${isYou ? ' (you)' : ''}'),
                  subtitle: Text(a.username),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(label: Text(a.role.label)),
                      const SizedBox(width: 8),
                      IconButton(tooltip: 'Edit', onPressed: () => _edit(context, a), icon: const Icon(Icons.edit_outlined)),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: isYou ? null : () => _delete(context, a),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

IconData _roleIcon(Role role) => switch (role) {
      Role.admin => Icons.admin_panel_settings_outlined,
      Role.display => Icons.tv,
      Role.officer => Icons.assignment_ind_outlined,
    };

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.auth, this.account});

  final AuthService auth;

  /// Null to add a new account.
  final Account? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _username = TextEditingController(text: widget.account?.username);
  late final _displayName = TextEditingController(text: widget.account?.displayName);
  final _password = TextEditingController();
  late Role _role = widget.account?.role ?? Role.officer;
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    String? error;
    try {
      error = await widget.auth.save(
        existing: widget.account,
        username: _username.text,
        displayName: _displayName.text,
        role: _role,
        password: _password.text,
      );
    } catch (e) {
      error = 'Something went wrong: $e';
    }
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
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.account != null;
    return AlertDialog(
      title: Text(editing ? 'Edit account' : 'Add account'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: editing ? 'New password' : 'Password',
                helperText: editing ? 'Leave empty to keep the current password.' : null,
              ),
            ),
            const SizedBox(height: 16),
            Text('Role', style: Theme.of(context).textTheme.labelLarge),
            RadioGroup<Role>(
              groupValue: _role,
              onChanged: (role) => setState(() => _role = role!),
              child: Column(
                children: [
                  for (final role in Role.values)
                    RadioListTile<Role>(
                      value: role,
                      title: Text(role.label),
                      subtitle: Text(role.description),
                      secondary: Icon(_roleIcon(role)),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
