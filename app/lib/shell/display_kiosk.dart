import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../auth/auth_service.dart';
import '../data/reports.dart';
import '../data/student_repository.dart';
import '../live/live_session.dart';
import '../serial/device_event.dart';
import '../serial/serial_connection.dart';
import '../serial/simulator.dart';
import '../theme/app_theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
import '../widgets/page_parts.dart';
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
    required this.simulator,
  });

  final AuthService auth;
  final SerialConnection connection;
  final LiveSession session;
  final StudentRepository students;
  final Reports reports;

  /// Demo mode, toggled with Ctrl+Shift+D (for showing the screen without an ESP32).
  final Simulator simulator;

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

  // When the current card tap started, to show the processing stages.
  String? _processingUid;
  DateTime _processingSince = DateTime.now();

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
    widget.session.addListener(_onSession);
    _loadTotals();
  }

  @override
  void dispose() {
    _reconnect.cancel();
    _clock.cancel();
    widget.students.removeListener(_loadTotals);
    widget.session.removeListener(_onSession);
    windowManager.removeListener(this);
    windowManager.setPreventClose(false);
    super.dispose();
  }

  void _onSession() {
    final uid = widget.session.processingUid;
    if (uid != _processingUid) {
      _processingUid = uid;
      _processingSince = DateTime.now();
    }
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

  // Also fixes a connection to the wrong port (e.g. the laptop's own COM1,
  // picked on the admin Live screen): it looks connected but never hears a card.
  void _connectIfNeeded() {
    try {
      final esp32Ports = SerialConnection.listPorts().where((p) => p.looksLikeEsp32).map((p) => p.name).toList();
      final connection = widget.connection;
      if (connection.isConnected && esp32Ports.contains(connection.portName)) return;
      if (esp32Ports.isNotEmpty) connection.connect(esp32Ports.first);
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
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true): widget.simulator.toggle,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      body: Container(
        color: EcoColors.background,
        padding: const EdgeInsets.all(28),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.connection, widget.session, widget.students, widget.simulator]),
          builder: (context, _) => Column(
            children: [
              FadeSlideIn(offset: const Offset(0, -12), child: _topBar(context)),
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: FadeSlideIn(delay: const Duration(milliseconds: 100), child: _heroPanel(context))),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 420,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(
                                child: FadeSlideIn(delay: const Duration(milliseconds: 200), child: _binCard(context)),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FadeSlideIn(delay: const Duration(milliseconds: 280), child: _todayCard(context)),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: FadeSlideIn(delay: const Duration(milliseconds: 360), child: _leaderboard(context)),
                          ),
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
    ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final connected = widget.connection.isConnected;
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$hour:${_now.minute.toString().padLeft(2, '0')}';
    final date = '${_weekdays[_now.weekday - 1]}, ${monthNames[_now.month - 1]} ${_now.day}';

    return Row(
      children: [
        const EcoLogo(size: 52),
        const SizedBox(width: 16),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EcoEarn', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Text('Recycle plastic bottles, earn points', style: TextStyle(color: EcoColors.muted, fontSize: 14)),
        ]),
        const Spacer(),
        _StatusPill(connected: connected, port: widget.connection.portName, demo: widget.simulator.running),
        const SizedBox(width: 28),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: time),
              TextSpan(
                text: _now.hour < 12 ? ' AM' : ' PM',
                style: const TextStyle(fontSize: 16, color: EcoColors.muted, fontWeight: FontWeight.w600),
              ),
            ]),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          Text(date, style: const TextStyle(color: EcoColors.muted, fontSize: 14)),
        ]),
        const SizedBox(width: 16),
        SquareIconButton(icon: Icons.lock_outline, tooltip: 'Exit display mode', onPressed: _unlock),
      ],
    );
  }

  // ---------- Main panel: idle → processing → result, on deep green ----------

  Widget _heroPanel(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(
          color: EcoColors.night,
          child: Stack(children: [
            const Positioned.fill(child: DriftingShapes()),
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(40), child: _hero(context))),
          ]),
        ),
      );

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
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 200), // old state leaves quickly, no messy overlap
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(animation), child: child),
      ),
      child: KeyedSubtree(key: key, child: Center(child: child)),
    );
  }

  Widget _idle(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _PulsingIcon(icon: Icons.contactless),
        const SizedBox(height: 40),
        const _HeroTitle('Tap your card to start'),
        const SizedBox(height: 14),
        const _HeroSubtitle('Then put your empty plastic bottle in the chamber.'),
        const SizedBox(height: 44),
        Wrap(
          spacing: 14,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final (i, (icon, label)) in const [
              (Icons.contactless, 'Tap card'),
              (Icons.local_drink_outlined, 'Insert bottle'),
              (Icons.stars_rounded, 'Earn points'),
            ].indexed)
              FadeSlideIn(
                delay: Duration(milliseconds: 250 + 120 * i),
                child: _Step(number: i + 1, icon: icon, label: label),
              ),
          ],
        ),
      ],
    );
  }

  Widget _processing(BuildContext context, String uid) {
    final student = widget.students.byUid(uid);
    if (student == null) {
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        _BigBadge(icon: Icons.person_search_outlined, color: EcoColors.amber),
        SizedBox(height: 36),
        _HeroTitle('Card not registered'),
        SizedBox(height: 14),
        _HeroSubtitle('Please ask the admin to register your card.'),
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 150,
        height: 150,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: EcoColors.lime, shape: BoxShape.circle),
        child: Text(
          InitialsAvatar.initials(student.name),
          style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, color: EcoColors.night),
        ),
      ),
      const SizedBox(height: 32),
      _HeroTitle('Hi, ${student.name.split(' ').first}!', size: 60),
      const SizedBox(height: 12),
      const _HeroSubtitle('Hold on while we process your bottle.'),
      const SizedBox(height: 40),
      _ProcessingTracker(since: _processingSince),
    ]);
  }

  Widget _accepted(BuildContext context, WeightEvent w) {
    final student = widget.students.byUid(w.uid);
    final grams = w.grams == w.grams.roundToDouble() ? w.grams.toStringAsFixed(0) : w.grams.toStringAsFixed(1);

    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 220,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          const Positioned.fill(child: _Burst()),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: w.points),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, n, _) => Text(
                '+$n',
                style: const TextStyle(
                  fontSize: 180,
                  fontWeight: FontWeight.w800,
                  color: EcoColors.lime,
                  height: 1,
                  letterSpacing: -6,
                ),
              ),
            ),
          ),
        ]),
      ),
      Text(
        w.points == 1 ? 'POINT EARNED' : 'POINTS EARNED',
        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4),
      ),
      const SizedBox(height: 28),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _ResultChip(icon: Icons.scale_outlined, text: '$grams g recycled'),
        if (student != null) ...[
          const SizedBox(width: 12),
          _ResultChip(icon: Icons.account_balance_wallet_outlined, text: 'Total: ${student.points} pts'),
        ],
      ]),
      const SizedBox(height: 24),
      _HeroSubtitle(
        student != null
            ? 'Thank you, ${student.name.split(' ').first}! Every bottle counts.'
            : 'Register this card with the admin to keep the points.',
      ),
    ]);
  }

  Widget _rejected(BuildContext context, RejectEvent r) {
    final message = switch (r.reason) {
      'too_heavy' => 'This item is too heavy. Only empty plastic bottles are accepted.',
      'bin_full' => 'The storage bin is full. Please wait for staff to empty it.',
      'no_item' => 'No bottle was detected. Please try again.',
      'mechanism' => 'The machine had a problem. Please call the admin.',
      _ => 'Please try again.',
    };
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const _BigBadge(icon: Icons.block, color: EcoColors.coral),
      const SizedBox(height: 36),
      const _HeroTitle('Bottle not accepted'),
      const SizedBox(height: 14),
      SizedBox(width: 600, child: _HeroSubtitle(message)),
    ]);
  }

  // ---------- Side panel ----------

  Widget _binCard(BuildContext context) {
    final level = widget.session.binLevel;
    final full = level != null && level >= binFullPercent;
    final color = full ? EcoColors.coral : (level != null && level >= 70 ? EcoColors.amber : EcoColors.emerald);
    return _KioskCard(
      child: Column(children: [
        const _CardTitle(icon: Icons.delete_outline, text: 'Bin level'),
        const SizedBox(height: 16),
        SizedBox.square(
          dimension: 110,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (level ?? 0) / 100),
            duration: Motion.slow,
            curve: Motion.curve,
            builder: (context, value, _) => Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 12,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
              Center(
                child: Text(
                  level == null ? '—' : '${(value * 100).round()}%',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Text(level == null ? 'Waiting for data' : (full ? 'Full, please empty' : 'Has space'), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _todayCard(BuildContext context) {
    final bottles = _today.fold(0, (sum, r) => sum + r.bottles);
    final grams = _today.fold(0.0, (sum, r) => sum + r.grams);
    return _KioskCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _CardTitle(icon: Icons.today_outlined, text: 'Today'),
        const SizedBox(height: 16),
        _CountUp(value: bottles.toDouble(), decimals: 0, color: EcoColors.emerald),
        const Text('bottles', style: TextStyle(color: EcoColors.muted)),
        const SizedBox(height: 12),
        _CountUp(value: grams / 1000, decimals: 2, color: EcoColors.teal),
        const Text('kg plastic', style: TextStyle(color: EcoColors.muted)),
      ]),
    );
  }

  Widget _leaderboard(BuildContext context) {
    final top = _month.where((r) => r.isRegistered && r.points > 0).take(5).toList();
    return _KioskCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CardTitle(
          icon: Icons.emoji_events_rounded,
          iconColor: EcoColors.amber,
          text: 'Top recyclers · ${monthNames[_now.month - 1]}',
        ),
        const SizedBox(height: 14),
        if (top.isEmpty)
          const Expanded(
            child: Center(
              child: Text('Be the first to recycle this month!',
                  textAlign: TextAlign.center, style: TextStyle(color: EcoColors.muted, fontSize: 16)),
            ),
          )
        else
          for (final (i, r) in top.indexed)
            FadeSlideIn(
              key: ValueKey('${r.name}-${r.points}'),
              delay: Duration(milliseconds: 80 * i),
              offset: const Offset(16, 0),
              child: _LeaderRow(rank: i + 1, row: r),
            ),
      ]),
    );
  }
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected, required this.port, required this.demo});

  final bool connected;
  final String? port;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final (color, textColor, text) = demo
        ? (EcoColors.sky, const Color(0xFF1E3A8A), 'Demo mode')
        : connected
            ? (EcoColors.emerald, EcoColors.forest, 'Machine ready · $port')
            : (EcoColors.amber, const Color(0xFF92400E), 'Connecting to machine…');
    return AnimatedContainer(
      duration: Motion.medium,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(children: [
        _Blink(color: color),
        const SizedBox(width: 10),
        Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: textColor)),
      ]),
    );
  }
}

/// A dot with a soft halo that keeps pulsing.
class _Blink extends StatefulWidget {
  const _Blink({required this.color});

  final Color color;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.45 * (1 - _controller.value)),
                spreadRadius: 7 * _controller.value,
              ),
            ],
          ),
        ),
      );
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle(this.text, {this.size = 54});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.1),
      );
}

class _HeroSubtitle extends StatelessWidget {
  const _HeroSubtitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 20, height: 1.5),
      );
}

/// Large icon on a tinted circle, for the "not registered" and "rejected" states.
class _BigBadge extends StatelessWidget {
  const _BigBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
        child: Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: 54),
          ),
        ),
      );
}

/// Live loaders while a bottle is processed: the three stages, an overall
/// progress bar and a running timer. The machine reports nothing between the
/// tap and the result, so they follow the firmware's timings (crush ~1.5 s,
/// drain 5 s, then weigh) and the bar slows near the end until the result comes.
class _ProcessingTracker extends StatefulWidget {
  const _ProcessingTracker({required this.since});

  final DateTime since;

  @override
  State<_ProcessingTracker> createState() => _ProcessingTrackerState();
}

class _ProcessingTrackerState extends State<_ProcessingTracker> with SingleTickerProviderStateMixin {
  static const _stages = [
    (Icons.compress, 'Crushing', 'Crushing your bottle'),
    (Icons.water_drop_outlined, 'Draining', 'Draining leftover liquid'),
    (Icons.scale_outlined, 'Weighing', 'Weighing your bottle'),
  ];

  // Only used to repaint every frame; the values come from the clock.
  late final _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ticker,
        builder: (context, _) {
          final elapsed = DateTime.now().difference(widget.since).inMilliseconds / 1000;
          final stage = elapsed < 1.5 ? 0 : (elapsed < 6.5 ? 1 : 2);
          // Linear up to 90% over the expected ~9 s, then creeps toward 98%.
          final progress = elapsed < 9 ? elapsed / 10 : 0.98 - 0.08 * math.exp(-(elapsed - 9) / 4);

          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (i, (icon, label, _)) in _stages.indexed) ...[
                if (i > 0) _StageLine(done: stage >= i),
                _Stage(icon: icon, label: label, state: stage > i ? 1 : (stage == i ? 0 : -1)),
              ],
            ]),
            const SizedBox(height: 32),
            SizedBox(
              width: 420,
              child: Column(children: [
                Row(children: [
                  Text(
                    '${_stages[stage].$3}…',
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(color: EcoColors.lime, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ]),
                const SizedBox(height: 10),
                _ShimmerBar(progress: progress, phase: _ticker.value),
                const SizedBox(height: 10),
                Text(
                  '${elapsed.floor()} s',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
              ]),
            ),
          ]);
        },
      );
}

/// Progress bar with a light band sweeping across the filled part.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.progress, required this.phase});

  final double progress;

  /// 0-1, moves the light band.
  final double phase;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: LayoutBuilder(
            builder: (context, box) {
              final filled = box.maxWidth * progress.clamp(0, 1);
              return Stack(children: [
                Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.1))),
                Positioned(left: 0, top: 0, bottom: 0, width: filled, child: const ColoredBox(color: EcoColors.lime)),
                Positioned(
                  left: filled * phase - 40,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: ColoredBox(color: Colors.white.withValues(alpha: filled > 40 ? 0.35 : 0)),
                ),
              ]);
            },
          ),
        ),
      );
}

/// One processing stage: done (1), in progress (0) or waiting (-1).
class _Stage extends StatelessWidget {
  const _Stage({required this.icon, required this.label, required this.state});

  final IconData icon;
  final String label;
  final int state;

  @override
  Widget build(BuildContext context) {
    final active = state == 0;
    final done = state == 1;
    return SizedBox(
      width: 110,
      child: Column(children: [
        AnimatedContainer(
          duration: Motion.medium,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? EcoColors.lime : (active ? Colors.white : Colors.white.withValues(alpha: 0.08)),
          ),
          child: active
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: CircularProgressIndicator(strokeWidth: 3, color: EcoColors.emerald),
                )
              : Icon(
                  done ? Icons.check_rounded : icon,
                  color: done ? EcoColors.night : Colors.white.withValues(alpha: 0.5),
                  size: 30,
                ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(
            color: state >= 0 ? Colors.white : Colors.white.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ]),
    );
  }
}

class _StageLine extends StatelessWidget {
  const _StageLine({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: AnimatedContainer(
          duration: Motion.medium,
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: done ? EcoColors.lime : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: EcoColors.lime, size: 20),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Dots that fly outward and fade once, behind the points number.
class _Burst extends StatefulWidget {
  const _Burst();

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _BurstPainter(_controller));
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const _colors = [EcoColors.lime, EcoColors.emerald, EcoColors.amber, Colors.white];

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(progress.value);
    final center = size.center(Offset.zero);
    const count = 18;
    for (var i = 0; i < count; i++) {
      final angle = i / count * 2 * math.pi + (i.isEven ? 0.12 : -0.08);
      final distance = (120 + (i % 3) * 50) * t;
      final radius = (i % 3 == 0 ? 7.0 : 4.5) * (1 - t * 0.6);
      final paint = Paint()..color = _colors[i % _colors.length].withValues(alpha: 1 - progress.value);
      canvas.drawCircle(center + Offset(math.cos(angle), math.sin(angle)) * distance, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => false;
}

class _KioskCard extends StatelessWidget {
  const _KioskCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: EcoColors.line),
        ),
        child: child,
      );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.icon, required this.text, this.iconColor = EcoColors.emerald});

  final IconData icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconBadge(icon: icon, color: iconColor, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: EcoColors.ink),
          ),
        ),
      ]);
}

/// A number that counts up (or down) to its new value.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.decimals, required this.color});

  final double value;
  final int decimals;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value),
        duration: const Duration(milliseconds: 900),
        curve: Motion.curve,
        builder: (context, v, _) => Text(
          v.toStringAsFixed(decimals),
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: color, height: 1.1, letterSpacing: -0.5),
        ),
      );
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.row});

  final int rank;
  final MonthlyRow row;

  static const _medals = [Color(0xFFF59E0B), Color(0xFF94A3B8), Color(0xFFB45309)];

  @override
  Widget build(BuildContext context) {
    final medal = rank <= 3 ? _medals[rank - 1] : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rank == 1 ? EcoColors.mint : EcoColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: medal ?? Colors.transparent),
          child: Text(
            '$rank',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: medal == null ? EcoColors.muted : Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        InitialsAvatar(name: row.name, size: 38, color: rank == 1 ? EcoColors.forest : EcoColors.emerald),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              [row.gradeSection, '${row.bottles} ${row.bottles == 1 ? 'bottle' : 'bottles'}'].where((s) => s.isNotEmpty).join(' · '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: EcoColors.muted, fontSize: 12),
            ),
          ]),
        ),
        Text('${row.points}', style: const TextStyle(fontSize: 18, color: EcoColors.forest, fontWeight: FontWeight.w800)),
        const Text(' pts', style: TextStyle(fontSize: 12, color: EcoColors.muted, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.icon, required this.label});

  final int number;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: EcoColors.lime),
            child: Text('$number', style: const TextStyle(color: EcoColors.night, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
        ]),
      );
}

/// A big lime circle with rings that keep expanding and fading, inviting a tap.
class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon({required this.icon});

  final IconData icon;

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 240,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(alignment: Alignment.center, children: [
            // Two rings, half a cycle apart.
            for (final offset in [0.0, 0.5])
              Builder(builder: (context) {
                final t = (_controller.value + offset) % 1;
                return Container(
                  width: 140 + 100 * t,
                  height: 140 + 100 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: EcoColors.lime.withValues(alpha: 0.5 * (1 - t)), width: 2),
                  ),
                );
              }),
            Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: EcoColors.lime),
              child: Icon(widget.icon, color: EcoColors.night, size: 70),
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
