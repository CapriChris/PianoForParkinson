import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rigid metronome arm: its tip and weight rotate about the same pivot.
class MetronomePendulum extends CustomPainter {
  const MetronomePendulum(this.position, this.color);

  final double position;
  final Color color;

  @visibleForTesting
  ({Offset pivot, Offset tip, Offset weight}) geometry(Size size) {
    final pivot = Offset(size.width / 2, size.height - 3);
    final length = math.max(0.0, size.height - 6);
    final angle = position.clamp(-1.0, 1.0) * .4;
    final direction = Offset(math.sin(angle), -math.cos(angle));
    return (
      pivot: pivot,
      tip: pivot + direction * length,
      weight: pivot + direction * (length * 2 / 3),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final arm = geometry(size);
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(3, size.height - 1),
      Offset(size.width - 3, size.height - 1),
      pen,
    );
    canvas.drawLine(arm.pivot, arm.tip, pen);
    canvas.drawCircle(
      arm.weight,
      (size.shortestSide / 10).clamp(2.5, 3.0),
      pen,
    );
  }

  @override
  bool shouldRepaint(MetronomePendulum oldDelegate) =>
      oldDelegate.position != position || oldDelegate.color != color;
}
