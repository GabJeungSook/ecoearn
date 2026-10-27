import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../shell/window_controls.dart';
import '../widgets/page_parts.dart';
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
  bool _showPassword = false;

  bool get _setup => !widget.auth.hasAccounts;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    String? error;
    try {
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
    } catch (e) {
      error = 'Something went wrong: $e';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          const Expanded(flex: 6, child: _HeroPanel()),
          Expanded(
            flex: 5,
            child: Stack(children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _form(context),
                  ),
                ),
              ),
              Positioned(
                top: 20,
                right: 20,
                child: SquareIconButton(
                  icon: Icons.power_settings_new,
                  tooltip: 'Quit EcoEarn',
                  onPressed: () => confirmQuit(context),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final passwordToggle = IconButton(
      tooltip: _showPassword ? 'Hide password' : 'Show password',
      onPressed: () => setState(() => _showPassword = !_showPassword),
      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_setup ? 'Welcome' : 'Welcome back', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          _setup
              ? 'First-time setup: create the admin account. It can manage students, reports and other accounts.'
              : 'Sign in to continue.',
          style: text.bodyMedium?.copyWith(color: EcoColors.muted),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _username,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
          onSubmitted: (_) => _submit(),
        ),
        if (_setup) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _displayName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined)),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: passwordToggle,
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_setup) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _confirm,
            obscureText: !_showPassword,
            decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EcoColors.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: EcoColors.coral),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, style: const TextStyle(color: EcoColors.coral))),
            ]),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(_setup ? 'Create admin account' : 'Sign in'),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) => Container(
        color: EcoColors.emerald,
        padding: const EdgeInsets.all(56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.recycling, color: EcoColors.emerald, size: 30),
              ),
              const SizedBox(width: 14),
              const Text('EcoEarn', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            const Text(
              'Turn plastic\ninto points.',
              style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w700, height: 1.05),
            ),
            const SizedBox(height: 16),
            Text(
              'Plastic Waste Disposal Management System',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16),
            ),
            const SizedBox(height: 40),
            const _Feature(icon: Icons.contactless, text: 'Tap your ID card'),
            const _Feature(icon: Icons.compress, text: 'Crush, drain and weigh your bottle'),
            const _Feature(icon: Icons.stars_rounded, text: 'Earn points for approved school fines'),
            const Spacer(),
          ],
        ),
      );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
        ]),
      );
}
