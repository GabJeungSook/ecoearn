import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The EcoEarn logo: a recycling mark on a green rounded tile.
class EcoLogo extends StatelessWidget {
  const EcoLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: EcoColors.emerald, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(Icons.recycling, color: Colors.white, size: size * 0.6),
      );
}

/// Circle with a person's initials, e.g. "JD" for Juan Dela Cruz.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40, this.color = EcoColors.emerald});

  final String name;
  final double size;
  final Color color;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
        child: Text(
          initials(name),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36),
        ),
      );
}
