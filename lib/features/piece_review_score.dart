import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/piano_piece.dart';
import '../domain/piece_trace.dart';
import '../ui/note_colors.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/note_label.dart';

class ReviewStaffLayout {
  ReviewStaffLayout(this.piece, this.measure, this.width, {this.scale = 1}) {
    minStep = math.min(
      0,
      [for (var i = 0; i < piece.keyCount; i++) piece.keyStep(i)]
          .reduce(math.min),
    );
    maxStep = math.max(
      10,
      [for (var i = 0; i < piece.keyCount; i++) piece.keyStep(i)]
          .reduce(math.max),
    );
  }
  final PianoPiece piece;
  final int measure;
  final double width, scale;
  late final int minStep, maxStep;
  double get gap => 18 * scale;
  double get height => (maxStep - minStep) * gap / 2 + 72 * scale;
  double pitchY(int step) => 30 * scale + (maxStep - step) * gap / 2;
  int get start => measure == 0
      ? 0
      : piece.pickupTicks > 0
      ? piece.pickupTicks + (measure - 1) * piece.barTicks
      : measure * piece.barTicks;
  int get end => math.min(
    piece.ticks,
    measure == 0 && piece.pickupTicks > 0
        ? piece.pickupTicks
        : start + piece.barTicks,
  );
  double x(num tick) =>
      40 * scale + (tick - start) / (end - start) * (width - 48 * scale);
  Rect rect(PieceNote note) => Rect.fromLTRB(
    x(math.max(start, note.startTick)),
    pitchY(note.isRest ? 6 : piece.keyStep(note.key)) - 10 * scale,
    x(math.min(end, note.endTick)),
    pitchY(note.isRest ? 6 : piece.keyStep(note.key)) + 10 * scale,
  );
  List<int> get indices => [
    for (var i = 0; i < piece.notes.length; i++)
      if (piece.notes[i].startTick < end && piece.notes[i].endTick > start) i,
  ];
  int? hit(Offset point) {
    int? found;
    var distance = double.infinity;
    for (final index in indices) {
      final box = rect(piece.notes[index]);
      if (box.inflate(14).contains(point)) {
        final d = (box.center - point).distanceSquared;
        if (d < distance) {
          found = index;
          distance = d;
        }
      }
    }
    return found;
  }
}

class ReviewStaff extends StatefulWidget {
  const ReviewStaff({
    super.key,
    required this.data,
    required this.measure,
    required this.playhead,
    required this.selection,
    required this.onNote,
    this.onRecordedNote,
    required this.userMode,
    required this.preservePauses,
    required this.chinese,
    this.scale = 1,
    this.referenceOnly = false,
    this.showMeasureLabel = true,
  });
  final PieceReviewData data;
  final int measure;
  final ValueNotifier<int> playhead, selection;
  final ValueChanged<int> onNote;
  final ValueChanged<Map<String, dynamic>>? onRecordedNote;
  final bool userMode, preservePauses, chinese;
  final double scale;
  final bool referenceOnly;
  final bool showMeasureLabel;

  @override
  State<ReviewStaff> createState() => _ReviewStaffState();
}

class _ReviewStaffState extends State<ReviewStaff> {
  ReviewStaffPainter? painter;
  PieceReviewData get data => widget.data;
  int get measure => widget.measure;
  double get scale => widget.scale;
  ValueNotifier<int> get playhead => widget.playhead;
  ValueNotifier<int> get selection => widget.selection;
  ValueChanged<int> get onNote => widget.onNote;
  bool get userMode => widget.userMode;
  bool get preservePauses => widget.preservePauses;
  bool get chinese => widget.chinese;
  @override
  void dispose() {
    painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final geometry = ReviewStaffLayout(
        data.piece,
        measure,
        bounds.maxWidth * scale,
        scale: scale,
      );
      final next = ReviewStaffPainter(
        data,
        geometry,
        context.qin,
        playhead,
        selection,
        userMode,
        preservePauses,
        widget.referenceOnly,
        scaler: musicTextScalerOf(context),
      );
      painter?.dispose();
      painter = next;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showMeasureLabel)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                chinese ? '第 ${measure + 1} 小节' : 'Bar ${measure + 1}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (!widget.showMeasureLabel) const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: geometry.width,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (event) {
                  for (final n in next.localTouches) {
                    if (n['matched_note'] != null) continue;
                    final tick =
                        (n['start_us'] as int) *
                        (data.record['tempo_bpm'] as int) *
                        data.piece.ticksPerBeat /
                        60000000;
                    final center = Offset(
                      geometry.x(tick),
                      geometry.pitchY(data.piece.keyStep(n['key'] as int)),
                    );
                    if ((center - event.localPosition).distance <= 12 * scale &&
                        widget.onRecordedNote != null) {
                      widget.onRecordedNote!(n);
                      return;
                    }
                  }
                  final index = geometry.hit(event.localPosition);
                  if (index != null) onNote(index);
                },
                child: Stack(
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        key: ValueKey('review-staff-$measure'),
                        size: Size(geometry.width, geometry.height),
                        painter: next,
                      ),
                    ),
                    for (final n in next.localTouches)
                      if (n['matched_note'] == null &&
                          widget.onRecordedNote != null)
                        Positioned.fromRect(
                          rect: Rect.fromCircle(
                            center: Offset(
                              geometry.x(
                                (n['start_us'] as int) *
                                    (data.record['tempo_bpm'] as int) *
                                    data.piece.ticksPerBeat /
                                    60000000,
                              ),
                              geometry.pitchY(
                                data.piece.keyStep(n['key'] as int),
                              ),
                            ),
                            radius: 12 * scale,
                          ),
                          child: Semantics(
                            key: ValueKey(
                              'recorded-touch-${data.touches.indexOf(n)}',
                            ),
                            button: true,
                            label: chinese
                                ? '实际错音 ${data.piece.keyLabel(n['key'] as int)}'
                                : 'Recorded wrong note ${data.piece.keyLabel(n['key'] as int)}',
                            onTap: () => widget.onRecordedNote!(n),
                            child: const IgnorePointer(
                              child: SizedBox.expand(),
                            ),
                          ),
                        ),
                    for (final index in geometry.indices)
                      Positioned.fromRect(
                        rect: geometry.rect(data.piece.notes[index]).inflate(8),
                        child: Semantics(
                          button: true,
                          label: chinese
                              ? '${data.piece.notes[index].isRest ? '休止符' : data.piece.keyLabel(data.piece.notes[index].key)}，${data.piece.notes[index].beats} 拍'
                              : '${data.piece.notes[index].isRest ? 'Rest' : data.piece.keyLabel(data.piece.notes[index].key)}, ${data.piece.notes[index].beats} beats',
                          onTap: () => onNote(index),
                          child: const IgnorePointer(child: SizedBox.expand()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ReviewStaffPainter extends CustomPainter {
  ReviewStaffPainter(
    this.data,
    this.g,
    this.palette,
    this.playhead,
    this.selection,
    this.userMode,
    this.preservePauses,
    this.referenceOnly, {
    this.scaler,
  }) : super(repaint: Listenable.merge([playhead, selection])) {
    final matched = Set<int>.from(data.record['matched_notes'] as List);
    for (final index in g.indices) {
      final n = data.piece.notes[index];
      rectangles[index] = g.rect(n);
      final label = n.isRest ? '0' : data.piece.keyLabel(n.key);
      final text = ScoreNoteLabel(
        label,
        TextStyle(
          fontSize: 18 * g.scale,
          fontWeight: FontWeight.w700,
          color: palette.ink,
        ),
        scaler: scaler ?? TextScaler.noScaling,
      );
      labels[index] = text;
      if (!n.isRest && matched.contains(data.piece.soundingIndex(index))) {
        hits.add(index);
      }
    }
    clef = TextPainter(
      text: TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontSize: 62 * g.scale,
          color: palette.muted,
          fontFamilyFallback: const ['Noto Music', 'serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    localTouches = [
      for (final n in data.touches)
        if (n['start_us'] >= data.tickUs(g.start) &&
            n['start_us'] < data.tickUs(g.end))
          n,
    ];
  }
  final PieceReviewData data;
  final ReviewStaffLayout g;
  final QinPalette palette;
  final ValueNotifier<int> playhead, selection;
  final bool userMode, preservePauses;
  final bool referenceOnly;
  final TextScaler? scaler;
  final rectangles = <int, Rect>{};
  final labels = <int, ScoreNoteLabel>{};
  final hits = <int>{};
  late final TextPainter clef;
  late final List<Map<String, dynamic>> localTouches;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = palette.line
      ..strokeWidth = 1;
    for (var step = 2; step <= 10; step += 2) {
      canvas.drawLine(
        Offset(0, g.pitchY(step)),
        Offset(size.width, g.pitchY(step)),
        pen,
      );
    }
    clef.paint(canvas, Offset(0, g.pitchY(6) - clef.height / 2));
    for (final entry in rectangles.entries) {
      final index = entry.key,
          n = data.piece.notes[index],
          rect = entry.value.deflate(1);
      final tone = n.isRest
          ? null
          : NoteColors.degree(data.piece.keyStep(n.key));
      pen
        ..style = PaintingStyle.fill
        ..color = tone == null
            ? palette.soft
            : tone.fill.withValues(
                alpha: referenceOnly || hits.contains(index) ? .94 : .25,
              );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(5 * g.scale)),
        pen,
      );
      pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = selection.value == index ? 3 : 1.5
        ..color = selection.value == index
            ? palette.warning
            : tone == null
            ? palette.edge
            : tone.ink;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(5 * g.scale)),
        pen,
      );
      if (!referenceOnly && hits.contains(index) && rect.width > 32 * g.scale) {
        final at = Offset(rect.right - 10 * g.scale, rect.center.dy);
        pen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = palette.ink;
        canvas.drawPath(
          Path()
            ..moveTo(at.dx - 4 * g.scale, at.dy)
            ..lineTo(at.dx - 1 * g.scale, at.dy + 3 * g.scale)
            ..lineTo(at.dx + 5 * g.scale, at.dy - 4 * g.scale),
          pen,
        );
      }
      if (n.startTick < g.start || n.endTick > g.end) {
        final x = n.endTick > g.end
            ? rect.right - 2 * g.scale
            : rect.left + 2 * g.scale;
        pen
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = palette.primary;
        canvas.drawLine(
          Offset(x - 4 * g.scale, rect.top - 5 * g.scale),
          Offset(x, rect.top - 2 * g.scale),
          pen,
        );
        canvas.drawLine(
          Offset(x - 4 * g.scale, rect.top + 1 * g.scale),
          Offset(x, rect.top - 2 * g.scale),
          pen,
        );
      }
      final text = labels[index]!;
      text.paintIn(
        canvas,
        Rect.fromLTRB(
          rect.left + 4,
          rect.top + 1,
          rect.right - 1,
          rect.bottom - 1,
        ),
      );
    }
    // Recorded wrong presses are drawn at their actual pitch and score time.
    for (final n in localTouches) {
      if (n['matched_note'] != null) continue;
      final tick =
          (n['start_us'] as int) *
          (data.record['tempo_bpm'] as int) *
          data.piece.ticksPerBeat /
          60000000;
      final center = Offset(
        g.x(tick),
        g.pitchY(data.piece.keyStep(n['key'] as int)),
      );
      pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.error;
      canvas.drawCircle(center, 8 * g.scale, pen);
      canvas.drawLine(center - Offset(3, 3), center + Offset(3, 3), pen);
      canvas.drawLine(center + Offset(-3, 3), center + Offset(3, -3), pen);
    }
    final scoreTime = data.scoreAt(
      playhead.value,
      preservePauses: userMode && preservePauses,
    );
    final tick =
        scoreTime *
        (data.record['tempo_bpm'] as int) *
        data.piece.ticksPerBeat /
        60000000;
    if (tick >= g.start && tick < g.end) {
      final x = g.x(tick);
      pen
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = palette.primary;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), pen);
    }
  }

  @override
  bool shouldRepaint(ReviewStaffPainter old) =>
      old.data != data ||
      old.g.width != g.width ||
      old.g.scale != g.scale ||
      old.palette != palette ||
      old.userMode != userMode ||
      old.referenceOnly != referenceOnly ||
      old.preservePauses != preservePauses ||
      old.scaler != scaler;
  void dispose() {
    clef.dispose();
    for (final t in labels.values) {
      t.dispose();
    }
  }
}
