import 'package:flutter/material.dart';

/// A labelled number tile, used in rows across the top of a screen.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? valueColor;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Text(label, style: text.labelLarge),
              ]),
              const SizedBox(height: 8),
              Text(value, style: text.headlineSmall?.copyWith(color: valueColor)),
              if (progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress, color: valueColor),
              ],
              const SizedBox(height: 4),
              Text(detail, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
