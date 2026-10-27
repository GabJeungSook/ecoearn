import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../auth/auth_service.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../live/live_session.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/stat_card.dart';

/// Display account: a big, student-facing screen locked in fullscreen. It
/// connects to the ESP32 by itself, and leaving it (including Alt+F4) needs
/// an admin password.
class DisplayKiosk extends StatefulWidget {
  const DisplayKiosk({
    super.key,
    required this.auth,
    required this.connection,
    required this.session,
    required this.students,
    required this.reports,
  });

  final AuthService auth;
  final SerialConnection connection;
  final LiveSession session;
  final StudentRepository students;
  final Reports reports;

  @override
  State<DisplayKiosk> createState() => _DisplayKioskState();
}

class _DisplayKioskState extends State<DisplayKiosk> with WindowListener {
  static const _reconnectEvery = Duration(seconds: 5);

  /// How long the "+3 points" result stays up before returning to "Tap your card".
  static const _showResultFor = Duration(seconds: 10);

  late final Timer _reconnect;
  late final Timer _clock;
  DateTime _now = DateTime.now();
  List<MonthlyRow> _today = const [];
  List<MonthlyRow> _month = const [];
  bool _unlocking = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    windowManager.setFullScreen(true); // in case the admin switched it off with F11
    _connectIfNeeded();
    _reconnect = Timer.periodic(_reconnectEvery, (_) => _connectIfNeeded());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    widget.students.addListener(_loadTotals); // reloaded after every saved deposit
    _loadTotals();
  }

  @override
  void dispose() {
    _reconnect.cancel();
    _clock.cancel();
    widget.students.removeListener(_loadTotals);
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    super.dispose();
  }

  Future<void> _loadTotals() async {
    final now = DateTime.now();
    final today = await widget.reports.day(now);
    final month = await widget.reports.monthly(now.year, now.month);
    if (mounted) {
      setState(() {
        _today = today;
        _month = month.rows;
      });
    }
  }

  void _connectIfNeeded() {
    if (widget.connection.isConnected) return;
    try {
      final port = SerialConnection.listPorts().where((p) => p.looksLikeEsp32).firstOrNull;
      if (port != null) widget.connection.connect(port.name);
    } catch (e) {
      debugPrint('Could not list serial ports: $e'); // try again on the next tick
    }
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
    return Scaffold(
      body: Container(
        color: EcoColors.background,
        padding: const EdgeInsets.all(28),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.connection, widget.session, widget.students]),
          builder: (context, _) => Column(
            children: [
              _topBar(context),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _KioskCard(padding: const EdgeInsets.all(40), child: _hero(context))),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 400,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(child: _binCard(context)),
                              const SizedBox(width: 16),
                              Expanded(child: _todayCard(context)),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          Expanded(child: _leaderboard(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final connected = widget.connection.isConnected;
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$hour:${_now.minute.toString().padLeft(2, '0')} ${_now.hour < 12 ? 'AM' : 'PM'}';
    final date = '${_weekdays[_now.weekday - 1]}, ${monthNames[_now.month - 1]} ${_now.day}';

    return Row(
      children: [
        const EcoLogo(size: 56),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('EcoEarn', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const Text('Recycle plastic bottles, earn points', style: TextStyle(color: EcoColors.muted)),
        ]),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(time, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          Text(date, style: const TextStyle(color: EcoColors.muted)),
        ]),
        const SizedBox(width: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: EcoColors.line),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(children: [
            Icon(Icons.circle, size: 10, color: connected ? EcoColors.emerald : EcoColors.amber),
            const SizedBox(width: 8),
            Text(connected ? 'Machine ready' : 'Connecting…',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Exit display mode',
          onPressed: _unlock,
          icon: const Icon(Icons.lock_outline, color: EcoColors.muted),
        ),
      ],
    );
  }

  // ---------- Main panel: idle → processing → result ----------

  Widget _hero(BuildContext context) {
    final session = widget.session;
    final processingUid = session.processingUid;
    final result = session.lastResult;
    final showResult = result != null && _now.difference(result.receivedAt) < _showResultFor;

    final (Key key, Widget child) = switch ((processingUid, showResult ? result : null)) {
      (final String uid, _) => (ValueKey('processing $uid'), _processing(context, uid)),
      (null, final WeightEvent w) => (ObjectKey(w), _accepted(context, w)),
      (null, final RejectEvent r) => (ObjectKey(r), _rejected(context, r)),
      _ => (const ValueKey('idle'), _idle(context)),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
      ),
      child: KeyedSubtree(key: key, child: Center(child: child)),
    );
  }

  Widget _idle(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PulsingIcon(icon: Icons.contactless, color: EcoColors.emerald),
        const SizedBox(height: 36),
        Text('Tap your card to start', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('Then put your empty plastic bottle in the chamber.',
            style: text.titleLarge?.copyWith(color: EcoColors.muted, fontWeight: FontWeight.w400)),
        const SizedBox(height: 40),
        const Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            _Step(number: 1, icon: Icons.contactless, label: 'Tap card', color: EcoColors.sky),
            _Step(number: 2, icon: Icons.local_drink_outlined, label: 'Insert bottle', color: EcoColors.teal),
            _Step(number: 3, icon: Icons.stars_rounded, label: 'Earn points', color: EcoColors.amber),
          ],
        ),
      ],
    );
  }

  Widget _processing(BuildContext context, String uid) {
    final text = Theme.of(context).textTheme;
    final student = widget.students.byUid(uid);
    if (student == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const IconBadge(icon: Icons.person_search_outlined, color: EcoColors.amber, size: 140),
        const SizedBox(height: 32),
        Text('Card not registered', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('Please ask the admin to register card $uid.',
            style: text.titleLarge?.copyWith(color: EcoColors.muted, fontWeight: FontWeight.w400)),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      InitialsAvatar(name: student.name, size: 150),
      const SizedBox(height: 32),
      Text('Hi, ${student.name.split(' ').first}!', style: text.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text('Crushing, draining and weighing your bottle…',
          style: text.titleLarge?.copyWith(color: EcoColors.muted, fontWeight: FontWeight.w400)),
      const SizedBox(height: 32),
      SizedBox(
        width: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const LinearProgressIndicator(minHeight: 8, backgroundColor: EcoColors.mint),
        ),
      ),
    ]);
  }

  Widget _accepted(BuildContext context, WeightEvent w) {
    final text = Theme.of(context).textTheme;
    final student = widget.students.byUid(w.uid);
    final grams = w.grams == w.grams.roundToDouble() ? w.grams.toStringAsFixed(0) : w.grams.toStringAsFixed(1);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: Text(
          '+${w.points}',
          style: const TextStyle(fontSize: 160, fontWeight: FontWeight.w800, color: EcoColors.emerald, height: 1),
        ),
      ),
      Text(w.points == 1 ? 'point' : 'points',
          style: text.displaySmall?.copyWith(color: EcoColors.emerald, fontWeight: FontWeight.w800)),
      const SizedBox(height: 24),
      Text('$grams g of plastic recycled', style: text.headlineSmall),
      const SizedBox(height: 20),
      if (student != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(color: EcoColors.mint, borderRadius: BorderRadius.circular(40)),
          child: Text(
            'Thank you, ${student.name.split(' ').first}!  Total: ${student.points} points',
            style: text.titleLarge?.copyWith(color: EcoColors.forest),
          ),
        )
      else
        Text('Register this card to keep the points.', style: text.titleLarge?.copyWith(color: EcoColors.amber)),
    ]);
  }

  Widget _rejected(BuildContext context, RejectEvent r) {
    final text = Theme.of(context).textTheme;
    final message = switch (r.reason) {
      'too_heavy' => 'This item is too heavy. Only empty plastic bottles are accepted.',
      'bin_full' => 'The storage bin is full. Please wait for staff to empty it.',
      'no_item' => 'No bottle was detected. Please try again.',
      'mechanism' => 'The machine had a problem. Please call the admin.',
      _ => 'Please try again.',
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const IconBadge(icon: Icons.block, color: EcoColors.coral, size: 140),
      const SizedBox(height: 32),
      Text('Bottle not accepted', style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SizedBox(
        width: 560,
        child: Text(message,
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: EcoColors.muted, fontWeight: FontWeight.w400)),
      ),
    ]);
  }

  // ---------- Side panel ----------

  Widget _binCard(BuildContext context) {
    final level = widget.session.binLevel;
    final full = level != null && level >= binFullPercent;
    final color = full ? EcoColors.coral : (level != null && level >= 70 ? EcoColors.amber : EcoColors.emerald);
    return _KioskCard(
      child: Column(children: [
        const _CardTitle('Bin level'),
        const SizedBox(height: 12),
        SizedBox.square(
          dimension: 104,
          child: Stack(fit: StackFit.expand, children: [
            CircularProgressIndicator(
              value: (level ?? 0) / 100,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
            Center(
              child: Text(level == null ? '—' : '$level%',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text(full ? 'Full!' : 'Has space', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _todayCard(BuildContext context) {
    final bottles = _today.fold(0, (sum, r) => sum + r.bottles);
    final grams = _today.fold(0.0, (sum, r) => sum + r.grams);
    return _KioskCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _CardTitle('Today'),
        const SizedBox(height: 14),
        _TodayNumber(value: '$bottles', label: 'bottles', color: EcoColors.emerald),
        const SizedBox(height: 10),
        _TodayNumber(value: (grams / 1000).toStringAsFixed(2), label: 'kg plastic', color: EcoColors.teal),
      ]),
    );
  }

  Widget _leaderboard(BuildContext context) {
    final top = _month.where((r) => r.isRegistered && r.points > 0).take(5).toList();
    return _KioskCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emoji_events_rounded, color: EcoColors.amber),
          const SizedBox(width: 8),
          Expanded(child: _CardTitle('Top recyclers · ${monthNames[_now.month - 1]}')),
        ]),
        const SizedBox(height: 12),
        if (top.isEmpty)
          const Expanded(
            child: Center(
              child: Text('Be the first to recycle this month!',
                  textAlign: TextAlign.center, style: TextStyle(color: EcoColors.muted, fontSize: 16)),
            ),
          )
        else
          for (final (i, r) in top.indexed) _LeaderRow(rank: i + 1, row: r),
      ]),
    );
  }
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class _KioskCard extends StatelessWidget {
  const _KioskCard({required this.child, this.padding = const EdgeInsets.all(20)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: EcoColors.line),
        ),
        child: child,
      );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: EcoColors.ink),
      );
}

class _TodayNumber extends StatelessWidget {
  const _TodayNumber({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color, height: 1.1)),
        Text(label, style: const TextStyle(color: EcoColors.muted)),
      ]);
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.row});

  final int rank;
  final MonthlyRow row;

  static const _medals = [Color(0xFFF59E0B), Color(0xFF94A3B8), Color(0xFFB45309)];

  @override
  Widget build(BuildContext context) {
    final medal = rank <= 3 ? _medals[rank - 1] : EcoColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('$rank', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: medal)),
        ),
        InitialsAvatar(name: row.name, size: 40, color: rank == 1 ? EcoColors.amber : EcoColors.emerald),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              [row.gradeSection, '${row.bottles} bottles'].where((s) => s.isNotEmpty).join(' · '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: EcoColors.muted, fontSize: 12),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: EcoColors.mint, borderRadius: BorderRadius.circular(20)),
          child: Text('${row.points} pts',
              style: const TextStyle(color: EcoColors.forest, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.label, required this.color});

  final int number;
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
      );
}

/// A big icon with a soft ring that keeps expanding and fading, inviting a tap.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 220,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(alignment: Alignment.center, children: [
            Container(
              width: 140 + 80 * _controller.value,
              height: 140 + 80 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.18 * (1 - _controller.value)),
              ),
            ),
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: EcoColors.emerald),
              child: Icon(widget.icon, color: Colors.white, size: 72),
            ),
          ]),
        ),
      );
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
