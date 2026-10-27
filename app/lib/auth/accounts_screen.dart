import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/page_parts.dart';
import '../widgets/stat_card.dart';
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
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              overline: '${auth.accounts.length} accounts',
              title: 'Accounts',
              actions: [
                SquareIconButton(
                  icon: Icons.add,
                  tooltip: 'Add account',
                  primary: true,
                  onPressed: () => _edit(context, null),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: ColumnHeadings(labels: ['Name', 'Username', 'Role'], flex: [4, 3, 3], trailingWidth: 96),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                children: [
                  for (final a in auth.accounts) _row(context, a),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Account a) {
    final isYou = a.id == auth.current?.id;
    return RowCard(
      onTap: () => _edit(context, a),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Row(children: [
            IconBadge(icon: _roleIcon(a.role), color: _roleColor(a.role), size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${a.displayName}${isYou ? '  (you)' : ''}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        Expanded(flex: 3, child: Text(a.username)),
        Expanded(
          flex: 3,
          child: Text(a.role.label, style: TextStyle(color: _roleColor(a.role), fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          width: 96,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(tooltip: 'Edit', onPressed: () => _edit(context, a), icon: const Icon(Icons.edit_outlined, size: 20)),
            IconButton(
              tooltip: 'Delete',
              onPressed: isYou ? null : () => _delete(context, a),
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          ]),
        ),
      ]),
    );
  }
}

Color _roleColor(Role role) => switch (role) {
      Role.admin => EcoColors.emerald,
      Role.display => EcoColors.sky,
      Role.officer => EcoColors.amber,
    };

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
