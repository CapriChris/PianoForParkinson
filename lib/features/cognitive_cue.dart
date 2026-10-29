import 'package:flutter/material.dart';

class ShapeMark extends StatelessWidget {
  const ShapeMark({super.key, required this.shape, this.size = 32, this.color});
  final int shape;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _ShapePainter(
        shape,
        color ?? Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape, this.color);
  final int shape;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    if (shape == 0) {
      canvas.drawPath(
        Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.bottom)
          ..lineTo(rect.left, rect.bottom)
          ..close(),
        pen,
      );
    } else if (shape == 1) {
      canvas.drawOval(rect, pen);
    } else {
      canvas.drawRect(rect, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.shape != shape || old.color != color;
}

class SignalSlots extends StatelessWidget {
  const SignalSlots({super.key, required this.position, required this.shape});
  final int position, shape;
  @override
  Widget build(BuildContext context) => Semantics(
    label: Localizations.localeOf(context).languageCode == 'zh'
        ? '${['三角', '圆', '方形'][shape]}在${['左', '中', '右'][position]}侧位置'
        : '${['Triangle', 'Circle', 'Square'][shape]} in ${['left', 'middle', 'right'][position]} slot',
    child: SizedBox(
      width: 270,
      height: 42,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: i == position
                      ? ShapeMark(shape: shape, size: 28)
                      : const SizedBox(),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class RestMark extends StatelessWidget {
  const RestMark({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 42,
    child: CustomPaint(
      painter: _RestPainter(Theme.of(context).colorScheme.onSurface),
    ),
  );
}

class _RestPainter extends CustomPainter {
  _RestPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(15, 4)
        ..lineTo(24, 13)
        ..lineTo(11, 21)
        ..lineTo(23, 29)
        ..quadraticBezierTo(5, 23, 12, 38),
      pen,
    );
  }

  @override
  bool shouldRepaint(covariant _RestPainter old) => old.color != color;
}
