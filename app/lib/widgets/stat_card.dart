import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final onCard = highlight ? Colors.white : EcoColors.ink;
    final muted = highlight ? Colors.white.withValues(alpha: 0.8) : EcoColors.muted;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlight ? EcoColors.emerald : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: highlight ? null : Border.all(color: EcoColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: SmallLabel(label, color: muted)),
              Icon(icon, size: 20, color: highlight ? Colors.white : color),
            ]),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: valueColor ?? onCard),
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: valueColor ?? color,
                  backgroundColor: EcoColors.field,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(detail, style: TextStyle(fontSize: 12, color: muted), overflow: TextOverflow.ellipsis),
          ],
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
          child: CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 4,
            strokeCap: StrokeCap.round,
            color: color,
            backgroundColor: EcoColors.field,
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${(value * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w700)),
          SmallLabel(label),
        ]),
      ]);
}
