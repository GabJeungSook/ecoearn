import 'package:flutter/material.dart';

/// Shared animation timings, so motion feels the same on every screen.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 560);
  static const curve = Curves.easeOutCubic;
}

/// Fades and slides its child into place once, when it first appears.
/// Give neighbours increasing [delay]s for a staggered entrance.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 18),
    this.duration = Motion.slow,
  });

  final Widget child;
  final Duration delay;

  /// Where the child starts, in pixels from its final position.
  final Offset offset;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.duration);
  late final _progress = CurvedAnimation(parent: _controller, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final t = _progress.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: widget.offset * (1 - t), child: child),
          );
        },
        child: widget.child,
      );
}

/// Like [IndexedStack] (every screen keeps its state), but the screen being
/// switched to fades and slides in.
class ScreenSwitcher extends StatelessWidget {
  const ScreenSwitcher({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: index,
        children: [
          for (final (i, child) in children.indexed) _FadeWhenShown(shown: i == index, child: child),
        ],
      );
}

class _FadeWhenShown extends StatefulWidget {
  const _FadeWhenShown({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  State<_FadeWhenShown> createState() => _FadeWhenShownState();
}

class _FadeWhenShownState extends State<_FadeWhenShown> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.medium, value: widget.shown ? 0 : 1);
  late final _progress = CurvedAnimation(parent: _controller, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    if (widget.shown) _controller.forward();
  }

  @override
  void didUpdateWidget(_FadeWhenShown old) {
    super.didUpdateWidget(old);
    if (widget.shown && !old.shown) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        builder: (context, child) => Opacity(
          opacity: _progress.value,
          child: Transform.translate(offset: Offset(0, 12 * (1 - _progress.value)), child: child),
        ),
        child: widget.child,
      );
}

/// Rebuilds with `true` while the mouse is over the child.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.cursor = MouseCursor.defer});

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      );
}
