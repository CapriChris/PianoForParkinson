import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keep the stored combining marks, but place their visual dots ourselves so
/// font-specific combining-mark positioning cannot overlap the degree number.
class ScoreNoteLabel {
  ScoreNoteLabel(
    String value,
    TextStyle style, {
    TextScaler scaler = TextScaler.noScaling,
  }) : highDots = '\u0307'.allMatches(value).length,
       lowDots = '\u0323'.allMatches(value).length,
       dotPaint = (Paint()
         ..color = style.color ?? Colors.black
         ..isAntiAlias = true),
       dotRadius = scaler.scale(style.fontSize ?? 14) * .09,
       gap = math.max(1.0, scaler.scale(style.fontSize ?? 14) * .07),
       text = (TextPainter(
         text: TextSpan(
           text: value.replaceAll(RegExp('[\u0307\u0323]'), ''),
           style: style,
         ),
         textDirection: TextDirection.ltr,
         textScaler: scaler,
       )..layout());

  final int highDots, lowDots;
  final Paint dotPaint;
  final double dotRadius, gap;
  final TextPainter text;
  // Higher octaves stack vertically above the degree; lower-octave dots
  // retain their existing position to its lower right.
  double get highSpace =>
      highDots == 0 ? 0 : highDots * (dotRadius * 2 + gap) - 3.0;
  double get width =>
      text.width + (lowDots == 0 ? 0 : gap + lowDots * (dotRadius * 2 + gap));
  double get height => text.height + highSpace;

  void paint(Canvas canvas, Offset at) {
    text.paint(canvas, at + Offset(0, highSpace));
    if (highDots > 0) {
      final match = RegExp(r'[1-7]').firstMatch(text.plainText);
      final boxes = match == null
          ? <TextBox>[]
          : text.getBoxesForSelection(
              TextSelection(baseOffset: match.start, extentOffset: match.end),
            );
      final center = boxes.isEmpty
          ? text.width / 2
          : (boxes.first.left + boxes.first.right) / 2;
      for (var i = 0; i < highDots; i++) {
        canvas.drawCircle(
          Offset(at.dx + center, at.dy + dotRadius + i * (dotRadius * 2 + gap)),
          dotRadius,
          dotPaint,
        );
      }
    }
    for (var i = 0; i < lowDots; i++) {
      final x =
          at.dx + text.width + gap + dotRadius + i * (dotRadius * 2 + gap);
      canvas.drawCircle(
        Offset(x, at.dy + highSpace + text.height * .8),
        dotRadius,
        dotPaint,
      );
    }
  }

  void paintIn(Canvas canvas, Rect bounds) {
    if (bounds.width <= 0 || bounds.height <= 0 || width <= 0 || height <= 0) {
      return;
    }
    final scale = math.min(
      1.0,
      math.min(bounds.width / width, bounds.height / height),
    );
    canvas.save();
    canvas.clipRect(bounds);
    canvas.translate(bounds.left, bounds.center.dy - height * scale / 2);
    canvas.scale(scale);
    paint(canvas, Offset.zero);
    canvas.restore();
  }

  void dispose() => text.dispose();
}

/// Key labels use the same placement as the score and still scale with text.
class NoteLabel extends StatefulWidget {
  const NoteLabel(this.value, {super.key, required this.style});
  final String value;
  final TextStyle style;
  @override
  State<NoteLabel> createState() => _NoteLabelState();
}

class _NoteLabelState extends State<NoteLabel> {
  ScoreNoteLabel? layout;
  String? lastValue;
  TextStyle? lastStyle;
  TextScaler? lastScaler;
  @override
  Widget build(BuildContext context) {
    if (!widget.value.contains('\u0307') && !widget.value.contains('\u0323')) {
      layout?.dispose();
      layout = null;
      lastValue = null;
      lastStyle = null;
      lastScaler = null;
      return Text(
        widget.value,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    if (layout == null ||
        lastValue != widget.value ||
        lastStyle != widget.style ||
        lastScaler != scaler) {
      layout?.dispose();
      layout = ScoreNoteLabel(widget.value, widget.style, scaler: scaler);
      lastValue = widget.value;
      lastStyle = widget.style;
      lastScaler = scaler;
    }
    final next = layout!;
    return Semantics(
      label: widget.value,
      child: CustomPaint(
        size: Size(next.width, next.height),
        painter: _NoteLabelPainter(next),
      ),
    );
  }

  @override
  void dispose() {
    layout?.dispose();
    super.dispose();
  }
}

class _NoteLabelPainter extends CustomPainter {
  const _NoteLabelPainter(this.layout);
  final ScoreNoteLabel layout;
  @override
  void paint(Canvas canvas, Size size) => layout.paint(canvas, Offset.zero);
  @override
  bool shouldRepaint(_NoteLabelPainter old) => old.layout != layout;
}
