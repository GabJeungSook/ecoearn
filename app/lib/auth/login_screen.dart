import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/window_controls.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
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
  int _errorCount = 0; // a new value replays the shake
  bool _busy = false;
  bool _showPassword = false;
  bool _capsLock = false;

  bool get _setup => !widget.auth.hasAccounts;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _capsLock = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
  }

  bool _onKey(KeyEvent event) {
    final caps = HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);
    if (caps != _capsLock && mounted) setState(() => _capsLock = caps);
    return false;
  }

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
      if (error != null) {
        _errorCount++;
        _password.clear();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
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
          const Expanded(flex: 11, child: _HeroPanel()),
          Expanded(
            flex: 9,
            child: Stack(children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 250),
                      offset: const Offset(28, 0),
                      child: _form(context),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 24,
                child: SquareIconButton(
                  icon: Icons.power_settings_new,
                  tooltip: 'Quit EcoEarn',
                  onPressed: () => confirmQuit(context),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  'EcoEarn · Plastic Waste Disposal Management System',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: EcoColors.muted),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final passwordToggle = IconButton(
      tooltip: _showPassword ? 'Hide password' : 'Show password',
      onPressed: () => setState(() => _showPassword = !_showPassword),
      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: EcoColors.mint, borderRadius: BorderRadius.circular(20)),
            child: Text(
              _setup ? 'FIRST-TIME SETUP' : 'SECURE SIGN-IN',
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: EcoColors.forest,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _setup ? 'Create the admin account' : 'Welcome back',
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15),
        ),
        const SizedBox(height: 10),
        Text(
          _setup
              ? 'This account manages students, reports and the other accounts. Keep the password safe.'
              : 'Sign in to manage deposits, students and reports.',
          style: const TextStyle(fontSize: 15, color: EcoColors.muted, height: 1.5),
        ),
        const SizedBox(height: 36),
        _Field(
          label: 'Username',
          child: TextField(
            controller: _username,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. admin', prefixIcon: Icon(Icons.person_outline, size: 20)),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (_setup)
          _Field(
            label: 'Your name',
            child: TextField(
              controller: _displayName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. Juan Dela Cruz',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
            ),
          ),
        _Field(
          label: 'Password',
          child: TextField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              hintText: '••••••••',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: passwordToggle,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        if (_setup)
          _Field(
            label: 'Confirm password',
            child: TextField(
              controller: _confirm,
              obscureText: !_showPassword,
              decoration: const InputDecoration(hintText: '••••••••', prefixIcon: Icon(Icons.lock_outline, size: 20)),
              onSubmitted: (_) => _submit(),
            ),
          ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          child: _capsLock
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Icon(Icons.keyboard_capslock, size: 16, color: EcoColors.amber),
                    SizedBox(width: 6),
                    Text('Caps Lock is on', style: TextStyle(fontSize: 13, color: EcoColors.amber)),
                  ]),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSize(
          duration: Motion.medium,
          curve: Motion.curve,
          child: _error == null ? const SizedBox(width: double.infinity) : _Shake(key: ValueKey(_errorCount), child: _errorBox()),
        ),
        const SizedBox(height: 12),
        _SubmitButton(
          label: _setup ? 'Create account and sign in' : 'Sign in',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _errorBox() => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EcoColors.coral.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EcoColors.coral.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: EcoColors.coral, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: const TextStyle(color: EcoColors.coral, fontWeight: FontWeight.w500))),
        ]),
      );
}

/// A form field with its label above it.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

/// Shakes sideways once when it appears (a wrong password, for example).
class _Shake extends StatelessWidget {
  const _Shake({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 480),
        builder: (context, t, child) => Transform.translate(
          offset: Offset(math.sin(t * math.pi * 6) * 10 * (1 - t), 0),
          child: child,
        ),
        child: child,
      );
}

/// Full-width main button: the arrow nudges right on hover, a spinner replaces
/// the label while busy.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => AnimatedContainer(
          duration: Motion.fast,
          height: 54,
          decoration: BoxDecoration(
            color: hovered && !busy ? EcoColors.forest : EcoColors.emerald,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: busy ? null : onPressed,
              child: AnimatedSwitcher(
                duration: Motion.fast,
                child: busy
                    ? const Center(
                        key: ValueKey('busy'),
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        ),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          AnimatedPadding(
                            duration: Motion.fast,
                            padding: EdgeInsets.only(left: hovered ? 14 : 8),
                            child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Left side: deep green panel with slowly drifting shapes, the headline and a
// looping demo of one deposit.

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) => Container(
        color: EcoColors.night,
        child: Stack(children: [
          const Positioned.fill(child: ClipRect(child: _DriftingShapes())),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 48, 56, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeSlideIn(
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: EcoColors.lime, borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.recycling, color: EcoColors.night, size: 26),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'EcoEarn',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                    ),
                  ]),
                ),
                const Spacer(),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 120),
                  child: Text(
                    'Turn plastic',
                    style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -2),
                  ),
                ),
                const FadeSlideIn(
                  delay: Duration(milliseconds: 220),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'into '),
                      TextSpan(text: 'points.', style: TextStyle(color: EcoColors.lime)),
                    ]),
                    style: TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -2),
                  ),
                ),
                const SizedBox(height: 20),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 320),
                  child: Text(
                    'Tap your ID, drop in a bottle, and earn points\nyou can use for approved school fines.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 17, height: 1.55),
                  ),
                ),
                const SizedBox(height: 40),
                const FadeSlideIn(delay: Duration(milliseconds: 450), child: _DepositDemo()),
                const Spacer(),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 600),
                  child: Wrap(spacing: 10, runSpacing: 10, children: const [
                    _Pill(icon: Icons.wifi_off_rounded, text: 'Works offline'),
                    _Pill(icon: Icons.contactless_outlined, text: 'RFID sign-in'),
                    _Pill(icon: Icons.insert_chart_outlined, text: 'Monthly reports'),
                  ]),
                ),
              ],
            ),
          ),
        ]),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: EcoColors.lime),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );
}

/// Soft circles and rings that drift slowly behind the hero text.
class _DriftingShapes extends StatefulWidget {
  const _DriftingShapes();

  @override
  State<_DriftingShapes> createState() => _DriftingShapesState();
}

class _DriftingShapesState extends State<_DriftingShapes> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _ShapesPainter(_controller)),
      );
}

class _ShapesPainter extends CustomPainter {
  _ShapesPainter(this.time) : super(repaint: time);

  final Animation<double> time;

  // (x, y as fractions of the panel, radius, filled?, phase)
  static const _shapes = [
    (0.92, 0.12, 170.0, true, 0.0),
    (0.80, 0.88, 120.0, false, 1.7),
    (0.10, 0.72, 70.0, false, 3.1),
    (0.62, 0.40, 260.0, false, 4.2),
    (0.30, 0.06, 40.0, true, 5.3),
    (0.98, 0.58, 54.0, true, 2.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final angle = time.value * 2 * math.pi;
    for (final (x, y, r, filled, phase) in _shapes) {
      final center = Offset(
        size.width * x + math.sin(angle + phase) * 24,
        size.height * y + math.cos(angle * 0.8 + phase) * 18,
      );
      final paint = Paint()
        ..color = (filled ? EcoColors.emerald : Colors.white).withValues(alpha: filled ? 0.16 : 0.07)
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_ShapesPainter old) => false;
}

/// A white card that plays one deposit on a loop: card tap, crush, weigh, points.
class _DepositDemo extends StatefulWidget {
  const _DepositDemo();

  @override
  State<_DepositDemo> createState() => _DepositDemoState();
}

class _DepositDemoState extends State<_DepositDemo> with SingleTickerProviderStateMixin {
  static const _stepTime = Duration(milliseconds: 2400);
  static const _steps = [
    (Icons.contactless, EcoColors.sky, 'Card tapped', 'Juan Dela Cruz · 12 - STEM A'),
    (Icons.compress, EcoColors.amber, 'Crushing & draining', 'Liquid drains away from the scale'),
    (Icons.scale_outlined, EcoColors.teal, 'Weighed: 24 g', 'Stable reading on the load cell'),
    (Icons.stars_rounded, EcoColors.emerald, '+2 points earned', 'Saved to the student\'s balance'),
  ];

  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final Timer _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_stepTime, (_) => setState(() => _step = (_step + 1) % _steps.length));
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, subtitle) = _steps[_step];
    return Container(
      width: 440,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LiveDot(pulse: _pulse),
          const SizedBox(width: 8),
          const Text('LIVE DEPOSIT', style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: EcoColors.muted)),
          const Spacer(),
          Text('Step ${_step + 1} of ${_steps.length}', style: const TextStyle(fontSize: 12, color: EcoColors.muted)),
        ]),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: Motion.medium,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(_step),
            children: [
              _PulsingIcon(icon: icon, color: color, pulse: _pulse),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: EcoColors.ink)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: EcoColors.muted)),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _StepBar(state: i < _step ? 1 : (i == _step ? 0 : -1), duration: _stepTime)),
          ],
        ]),
      ]),
    );
  }
}

/// One segment of the demo's progress: done (1), filling (0) or waiting (-1).
class _StepBar extends StatelessWidget {
  const _StepBar({required this.state, required this.duration});

  final int state;
  final Duration duration;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: Stack(children: [
            const Positioned.fill(child: ColoredBox(color: EcoColors.field)),
            if (state == 1) const Positioned.fill(child: ColoredBox(color: EcoColors.emerald)),
            if (state == 0)
              TweenAnimationBuilder<double>(
                key: UniqueKey(),
                tween: Tween(begin: 0, end: 1),
                duration: duration,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: t,
                  child: const ColoredBox(color: EcoColors.emerald),
                ),
              ),
          ]),
        ),
      );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: pulse,
        builder: (context, _) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: EcoColors.emerald,
            boxShadow: [
              BoxShadow(
                color: EcoColors.emerald.withValues(alpha: 0.5 * (1 - pulse.value)),
                spreadRadius: 6 * pulse.value,
              ),
            ],
          ),
        ),
      );
}

/// Icon on a tinted circle with a ring that keeps expanding and fading.
class _PulsingIcon extends StatelessWidget {
  const _PulsingIcon({required this.icon, required this.color, required this.pulse});

  final IconData icon;
  final Color color;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 56,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, child) => Stack(alignment: Alignment.center, children: [
            Container(
              width: 44 + 12 * pulse.value,
              height: 44 + 12 * pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.35 * (1 - pulse.value)), width: 2),
              ),
            ),
            child!,
          ]),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      );
}
