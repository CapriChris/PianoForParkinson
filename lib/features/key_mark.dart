import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Consistent outlines for the keyboard's supplementary marks.
/// Cognitive task cues continue to use the existing ShapeMark painter.
class KeyMark extends StatelessWidget {
  const KeyMark({super.key, required this.shape, required this.color});
  final int shape;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.textScalerOf(context).scale(20).clamp(20.0, 30.0);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _KeyMarkPainter(shape, color)),
      ),
    );
  }
}

class _KeyMarkPainter extends CustomPainter {
  _KeyMarkPainter(this.shape, this.color);
  final int shape;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    if (shape == 1) {
      canvas.drawOval(rect, pen);
      return;
    }
    if (shape == 2) {
      canvas.drawRect(rect, pen);
      return;
    }
    final path = Path();
    if (shape == 0) {
      path.moveTo(rect.center.dx, rect.top);
      path.lineTo(rect.right, rect.bottom);
      path.lineTo(rect.left, rect.bottom);
    } else if (shape == 3) {
      path.moveTo(rect.center.dx, rect.top);
      path.lineTo(rect.right, rect.center.dy);
      path.lineTo(rect.center.dx, rect.bottom);
      path.lineTo(rect.left, rect.center.dy);
    } else if (shape == 5) {
      for (var i = 0; i < 6; i++) {
        final angle = i * math.pi / 3;
        final point =
            rect.center +
            Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    } else if (shape == 6) {
      final inset = rect.width / 3;
      path.moveTo(rect.left + inset, rect.top);
      path.lineTo(rect.right - inset, rect.top);
      path.lineTo(rect.right - inset, rect.top + inset);
      path.lineTo(rect.right, rect.top + inset);
      path.lineTo(rect.right, rect.bottom - inset);
      path.lineTo(rect.right - inset, rect.bottom - inset);
      path.lineTo(rect.right - inset, rect.bottom);
      path.lineTo(rect.left + inset, rect.bottom);
      path.lineTo(rect.left + inset, rect.bottom - inset);
      path.lineTo(rect.left, rect.bottom - inset);
      path.lineTo(rect.left, rect.top + inset);
      path.lineTo(rect.left + inset, rect.top + inset);
    } else {
      for (var i = 0; i < 10; i++) {
        final angle = -math.pi / 2 + i * math.pi / 5;
        final radius = rect.width / 2 * (i.isEven ? 1 : .45);
        final point =
            rect.center + Offset(math.cos(angle), math.sin(angle)) * radius;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    }
    canvas.drawPath(path..close(), pen);
  }

  @override
  bool shouldRepaint(_KeyMarkPainter old) =>
      old.shape != shape || old.color != color;
}
