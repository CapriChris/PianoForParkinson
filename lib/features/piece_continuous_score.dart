import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/piano_piece.dart';
import '../domain/piece_trace.dart';
import '../ui/note_colors.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/note_label.dart';
import 'piece_review_score.dart';

/// A single, continuous staff. Horizontal distances are proportional to beats.
class ContinuousScoreLayout {
  ContinuousScoreLayout(this.piece, this.viewportWidth)
    : pitch = ReviewStaffLayout(piece, 0, viewportWidth);
  final PianoPiece piece;
  final double viewportWidth;
  final ReviewStaffLayout pitch;
  // origin is the fixed play line; four beats precede the first score note.
  static const double origin = 48, beatWidth = 72;
  static const int leadBeats = 4;
  double get width =>
      math.max(viewportWidth, x(piece.ticks) + viewportWidth - origin);
  double get height => pitch.height;
  double x(num tick) =>
      origin + leadBeats * beatWidth + tick * beatWidth / piece.ticksPerBeat;
  static double offsetAt(int microseconds, int tempo) =>
      (leadBeats + microseconds * tempo / 60000000) * beatWidth;
  static int timeAt(double offset, int tempo) =>
      ((offset / beatWidth - leadBeats) * 60000000 / tempo).round();
  Rect rect(PieceNote n) => Rect.fromLTRB(
    x(n.startTick),
    pitch.pitchY(n.isRest ? 6 : piece.keyStep(n.key)) - 10,
    x(n.endTick),
    pitch.pitchY(n.isRest ? 6 : piece.keyStep(n.key)) + 10,
  );
  List<int> get barTicks {
    final result = <int>[];
    var tick = piece.pickupTicks > 0 ? piece.pickupTicks : piece.barTicks;
    while (tick < piece.ticks) {
      result.add(tick);
      tick += piece.barTicks;
    }
    return result;
  }

  int? hit(Offset point) {
    int? found;
    var distance = double.infinity;
    for (var i = 0; i < piece.notes.length; i++) {
      final box = rect(piece.notes[i]);
      if (box.inflate(8).contains(point)) {
        final next = (box.center - point).distanceSquared;
        if (next < distance) {
          found = i;
          distance = next;
        }
      }
    }
    return found;
  }
}

class PieceContinuousScore extends StatefulWidget {
  const PieceContinuousScore({
    super.key,
    required this.data,
    required this.selection,
    required this.onNote,
    required this.chinese,
    required this.viewportWidth,
  });
  final PieceReviewData data;
  final ValueNotifier<int> selection;
  final ValueChanged<int> onNote;
  final bool chinese;
  final double viewportWidth;
  @override
  State<PieceContinuousScore> createState() => _PieceContinuousScoreState();
}

class _PieceContinuousScoreState extends State<PieceContinuousScore> {
  ContinuousScorePainter? painter;
  @override
  void dispose() {
    painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final g = ContinuousScoreLayout(widget.data.piece, widget.viewportWidth);
      final next = ContinuousScorePainter(
        widget.data,
        g,
        context.qin,
        widget.selection,
        scaler: musicTextScalerOf(context),
      );
      painter?.dispose();
      painter = next;
      return SizedBox(
        width: g.width,
        height: g.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) {
            final index = g.hit(event.localPosition);
            if (index != null) widget.onNote(index);
          },
          child: Stack(
            children: [
              CustomPaint(
                key: const ValueKey('continuous-score'),
                size: Size(g.width, g.height),
                painter: next,
              ),
              for (var i = 0; i < widget.data.piece.notes.length; i++)
                Positioned.fromRect(
                  rect: g.rect(widget.data.piece.notes[i]).inflate(6),
                  child: Semantics(
                    button: true,
                    label: widget.chinese
                        ? '${widget.data.piece.notes[i].isRest ? '休止符' : widget.data.piece.keyLabel(widget.data.piece.notes[i].key)}，${widget.data.piece.notes[i].beats} 拍'
                        : '${widget.data.piece.notes[i].isRest ? 'Rest' : widget.data.piece.keyLabel(widget.data.piece.notes[i].key)}, ${widget.data.piece.notes[i].beats} beats',
                    onTap: () => widget.onNote(i),
                    child: const IgnorePointer(child: SizedBox.expand()),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ContinuousScorePainter extends CustomPainter {
  ContinuousScorePainter(
    this.data,
    this.g,
    this.palette,
    this.selection, {
    this.scaler,
  }) : super(repaint: selection) {
    for (var i = 0; i < data.piece.notes.length; i++) {
      final n = data.piece.notes[i];
      labels.add(
        ScoreNoteLabel(
          n.isRest ? '0' : data.piece.keyLabel(n.key),
          TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.ink,
          ),
          scaler: scaler ?? TextScaler.noScaling,
        ),
      );
    }
  }
  final PieceReviewData data;
  final ContinuousScoreLayout g;
  final QinPalette palette;
  final ValueNotifier<int> selection;
  final TextScaler? scaler;
  final labels = <ScoreNoteLabel>[];

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = palette.line
      ..strokeWidth = 1;
    for (var step = 2; step <= 10; step += 2) {
      canvas.drawLine(
        Offset(0, g.pitch.pitchY(step)),
        Offset(size.width, g.pitch.pitchY(step)),
        pen,
      );
    }
    for (final tick in g.barTicks) {
      canvas.drawLine(
        Offset(g.x(tick), g.pitch.pitchY(10)),
        Offset(g.x(tick), g.pitch.pitchY(2)),
        pen,
      );
    }
    for (var i = 0; i < data.piece.notes.length; i++) {
      final n = data.piece.notes[i], rect = g.rect(n).deflate(1);
      final tone = n.isRest
          ? null
          : NoteColors.degree(data.piece.keyStep(n.key));
      pen
        ..style = PaintingStyle.fill
        ..color = tone?.fill ?? palette.soft;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        pen,
      );
      pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = selection.value == i ? 3 : 1.5
        ..color = selection.value == i
            ? palette.warning
            : (tone?.ink ?? palette.edge);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        pen,
      );
      labels[i].paintIn(
        canvas,
        Rect.fromLTRB(
          rect.left + 4,
          rect.top + 1,
          rect.right - 1,
          rect.bottom - 1,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(ContinuousScorePainter old) =>
      old.data != data ||
      old.g.width != g.width ||
      old.palette != palette ||
      old.scaler != scaler;
  void dispose() {
    for (final label in labels) {
      label.dispose();
    }
  }
}

/// The clef, count-in and play line remain anchored while the score scrolls.
class FixedScoreGuide extends StatefulWidget {
  const FixedScoreGuide({
    super.key,
    required this.piece,
    required this.tempo,
    required this.timeline,
    required this.counting,
  });
  final PianoPiece piece;
  final int tempo;
  final ValueNotifier<int> timeline;
  final bool counting;
  @override
  State<FixedScoreGuide> createState() => _FixedScoreGuideState();
}

class _FixedScoreGuideState extends State<FixedScoreGuide> {
  FixedScoreGuidePainter? painter;
  @override
  void dispose() {
    painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = FixedScoreGuidePainter(
      widget.piece,
      widget.tempo,
      context.qin,
      widget.timeline,
      widget.counting,
    );
    painter?.dispose();
    painter = next;
    return IgnorePointer(
      child: CustomPaint(
        key: const ValueKey('fixed-score-guide'),
        painter: next,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class FixedScoreGuidePainter extends CustomPainter {
  FixedScoreGuidePainter(
    this.piece,
    this.tempo,
    this.palette,
    this.timeline,
    this.counting,
  ) : super(repaint: timeline) {
    clef = TextPainter(
      text: TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontSize: 62,
          color: palette.muted,
          fontFamilyFallback: const ['Noto Music', 'serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
  final PianoPiece piece;
  final int tempo;
  final QinPalette palette;
  final ValueNotifier<int> timeline;
  final bool counting;
  late final TextPainter clef;
  @override
  void paint(Canvas canvas, Size size) {
    final g = ReviewStaffLayout(piece, 0, size.width);
    final pen = Paint()..color = palette.surface;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, ContinuousScoreLayout.origin, size.height),
      pen,
    );
    pen
      ..color = palette.line
      ..strokeWidth = 1;
    for (var step = 2; step <= 10; step += 2) {
      canvas.drawLine(
        Offset(0, g.pitchY(step)),
        Offset(ContinuousScoreLayout.origin, g.pitchY(step)),
        pen,
      );
    }
    clef.paint(canvas, Offset(0, g.pitchY(6) - clef.height / 2));
    pen
      ..color = palette.primary
      ..strokeWidth = 3;
    canvas.drawLine(
      Offset(ContinuousScoreLayout.origin, 8),
      Offset(ContinuousScoreLayout.origin, size.height - 8),
      pen,
    );
    if (timeline.value < 0) {
      final beat = 60000000 ~/ tempo;
      final current = ((timeline.value + 4 * beat) ~/ beat).clamp(0, 3);
      for (var i = 0; i < 4; i++) {
        pen
          ..style = PaintingStyle.fill
          ..color = counting && i == current ? palette.primary : palette.line;
        canvas.drawCircle(Offset(58 + i * 13, 7), 3.5, pen);
      }
    }
  }

  @override
  bool shouldRepaint(FixedScoreGuidePainter old) =>
      old.piece != piece ||
      old.tempo != tempo ||
      old.palette != palette ||
      old.counting != counting;
  void dispose() => clef.dispose();
}
