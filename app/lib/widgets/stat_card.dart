import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// A labelled number tile, used in rows across the top of a screen.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.color = EcoColors.emerald,
    this.valueColor,
    this.progress,
    this.highlight = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  /// Accent for the icon and progress bar.
  final Color color;
  final Color? valueColor;
  final double? progress;

  /// Solid accent card with white text, for the screen's key number.
  final bool highlight;

  /// Shows a spinner and a moving bar, e.g. while a bottle is processed.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final onCard = highlight ? Colors.white : EcoColors.ink;
    final muted = highlight ? Colors.white.withValues(alpha: 0.8) : EcoColors.muted;

    return Expanded(
      child: FadeSlideIn(
        offset: const Offset(0, 14),
        child: HoverBuilder(
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.all(20),
            transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: highlight ? EcoColors.emerald : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: highlight
                  ? null
                  : Border.all(color: hovered ? color.withValues(alpha: 0.4) : EcoColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: SmallLabel(label, color: muted)),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: highlight ? Colors.white.withValues(alpha: 0.18) : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: highlight ? Colors.white : color,
                            ),
                          )
                        : Icon(icon, size: 18, color: highlight ? Colors.white : color),
                  ),
                ]),
                const SizedBox(height: 8),
                // A changed value slides up into place.
                AnimatedSwitcher(
                  duration: Motion.medium,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: valueColor ?? onCard,
                    ),
                  ),
                ),
                if (loading) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      color: highlight ? Colors.white : color,
                      backgroundColor: highlight ? Colors.white.withValues(alpha: 0.2) : EcoColors.field,
                    ),
                  ),
                ] else if (progress != null) ...[
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: progress!.clamp(0, 1)),
                    duration: Motion.slow,
                    curve: Motion.curve,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        color: valueColor ?? color,
                        backgroundColor: EcoColors.field,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(detail, style: TextStyle(fontSize: 12, color: muted), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small grey caption, e.g. above a value or a group of values.
class SmallLabel extends StatelessWidget {
  const SmallLabel(this.text, {super.key, this.color = EcoColors.muted});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      );
}

/// An icon on a soft tinted rounded square.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

/// Round percentage ring with a value in the middle and a caption beside it.
class RingStat extends StatelessWidget {
  const RingStat({super.key, required this.value, required this.label, this.color = EcoColors.emerald});

  /// 0.0–1.0
  final double value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox.square(
          dimension: 34,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: Motion.slow,
            curve: Motion.curve,
            builder: (context, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: EcoColors.field,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${(value * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            SmallLabel(label),
          ]),
        ),
      ]);
}
