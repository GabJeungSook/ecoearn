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

  /// Accent for the icon badge and progress bar.
  final Color color;
  final Color? valueColor;
  final double? progress;

  /// Bright green gradient card with white text, for the screen's key number.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final onCard = highlight ? Colors.white : EcoColors.ink;
    final muted = highlight ? Colors.white.withValues(alpha: 0.8) : EcoColors.muted;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: highlight ? null : Colors.white,
          gradient: highlight ? EcoColors.highlightGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: highlight ? null : Border.all(color: const Color(0xFFE2EBE5)),
          boxShadow: [
            BoxShadow(
              color: (highlight ? EcoColors.emerald : Colors.black).withValues(alpha: highlight ? 0.28 : 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconBadge(icon: icon, color: highlight ? Colors.white : color, onGradient: highlight),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: text.labelLarge?.copyWith(color: muted), overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.headlineMedium?.copyWith(color: valueColor ?? onCard, fontWeight: FontWeight.w800),
            ),
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: valueColor ?? color,
                  backgroundColor: (valueColor ?? color).withValues(alpha: 0.15),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(detail, style: text.bodySmall?.copyWith(color: muted), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// An icon on a soft tinted rounded square.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 40, this.onGradient = false});

  final IconData icon;
  final Color color;
  final double size;
  final bool onGradient;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: onGradient ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, color: color, size: size * 0.55),
      );
}
