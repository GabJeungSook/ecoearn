import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft circles and rings that drift slowly, for the deep green hero panels
/// (sign-in page, kiosk). Clip it: some shapes reach past the edges.
class DriftingShapes extends StatefulWidget {
  const DriftingShapes({super.key});

  @override
  State<DriftingShapes> createState() => _DriftingShapesState();
}

class _DriftingShapesState extends State<DriftingShapes> with SingleTickerProviderStateMixin {
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
