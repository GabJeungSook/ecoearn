import 'package:flutter/material.dart';

import 'account.dart';
import 'auth_service.dart';

/// Sign-in form. On first run (no accounts yet) it creates the admin account instead.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _setup => !widget.auth.hasAccounts;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    String? error;
    if (_setup) {
      if (_password.text != _confirm.text) {
        error = 'The two passwords don\'t match.';
      } else {
        error = await widget.auth.save(
          username: _username.text,
          displayName: _displayName.text,
          role: Role.admin,
          password: _password.text,
        );
      }
      error ??= await widget.auth.login(_username.text, _password.text);
    } else {
      error = await widget.auth.login(_username.text, _password.text);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error != null) _password.clear();
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 400,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.recycling, size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('EcoEarn', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                    Text('Plastic Waste Disposal Management System',
                        textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 24),
                    if (_setup) ...[
                      Text('First-time setup: create the admin account.', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _username,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_setup)
                      TextField(
                        controller: _displayName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined)),
                      ),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_setup)
                      TextField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                        onSubmitted: (_) => _submit(),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _busy
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_setup ? 'Create admin account' : 'Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
