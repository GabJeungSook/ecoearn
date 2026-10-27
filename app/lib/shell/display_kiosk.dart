import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../auth/auth_service.dart';
import '../data/deposit_recorder.dart';
import '../data/student_repository.dart';
import '../live/live_screen.dart';
import '../live/live_session.dart';
import '../serial/serial_connection.dart';

/// Display account: the Live screen locked in fullscreen. It connects to the
/// ESP32 by itself, and leaving it (including Alt+F4) needs an admin password.
class DisplayKiosk extends StatefulWidget {
  const DisplayKiosk({
    super.key,
    required this.auth,
    required this.connection,
    required this.session,
    required this.students,
    required this.recorder,
  });

  final AuthService auth;
  final SerialConnection connection;
  final LiveSession session;
  final StudentRepository students;
  final DepositRecorder recorder;

  @override
  State<DisplayKiosk> createState() => _DisplayKioskState();
}

class _DisplayKioskState extends State<DisplayKiosk> with WindowListener {
  static const _reconnectEvery = Duration(seconds: 5);

  late final Timer _reconnect;
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    windowManager.setFullScreen(true);
    _connectIfNeeded();
    _reconnect = Timer.periodic(_reconnectEvery, (_) => _connectIfNeeded());
  }

  @override
  void dispose() {
    _reconnect.cancel();
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    windowManager.setFullScreen(false);
    super.dispose();
  }

  void _connectIfNeeded() {
    if (widget.connection.isConnected) return;
    final port = SerialConnection.listPorts().where((p) => p.looksLikeEsp32).firstOrNull;
    if (port != null) widget.connection.connect(port.name);
  }

  // Closing the window is blocked; ask for the admin password instead.
  @override
  void onWindowClose() => _unlock();

  Future<void> _unlock() async {
    if (_unlocking) return;
    _unlocking = true;
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => _UnlockDialog(auth: widget.auth),
    );
    _unlocking = false;
    if (unlocked == true) widget.auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: theme.colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.recycling, size: 36, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text('EcoEarn', style: theme.textTheme.headlineMedium),
                const SizedBox(width: 16),
                Text('Tap your card, then insert your bottle', style: theme.textTheme.titleMedium),
                const Spacer(),
                ListenableBuilder(
                  listenable: widget.connection,
                  builder: (context, _) {
                    final connected = widget.connection.isConnected;
                    return Row(children: [
                      Icon(Icons.circle, size: 12, color: connected ? Colors.green : theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Text(connected ? 'Machine connected' : 'Connecting to machine…'),
                    ]);
                  },
                ),
                const SizedBox(width: 16),
                IconButton(tooltip: 'Exit display mode', onPressed: _unlock, icon: const Icon(Icons.lock_outline)),
              ],
            ),
          ),
          Expanded(
            child: LiveScreen(
              connection: widget.connection,
              session: widget.session,
              students: widget.students,
              recorder: widget.recorder,
              kiosk: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.auth});

  final AuthService auth;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    String? error;
    try {
      if (!await widget.auth.isAdminPassword(_password.text)) error = 'Wrong admin password.';
    } catch (e) {
      error = 'Something went wrong: $e';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _checking = false;
        _error = error;
        _password.clear();
      });
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Exit display mode'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Admin password', errorText: _error),
            onSubmitted: (_) => _check(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: _checking ? null : _check, child: const Text('Unlock')),
        ],
      );
}
