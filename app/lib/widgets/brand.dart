import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The EcoEarn logo: a recycling mark on a bright green rounded tile.
class EcoLogo extends StatelessWidget {
  const EcoLogo({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [EcoColors.mint, EcoColors.emerald]),
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [
            BoxShadow(color: EcoColors.mint.withValues(alpha: 0.35), blurRadius: size * 0.4, offset: Offset(0, size * 0.1)),
          ],
        ),
        child: Icon(Icons.recycling, color: Colors.white, size: size * 0.62),
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
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.75), color]),
        ),
        child: Text(
          initials(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.38),
        ),
      );
}
