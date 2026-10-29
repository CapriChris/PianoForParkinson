import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/piano_piece.dart';
import '../domain/scrolling_piece.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/note_label.dart';
import '../ui/note_colors.dart';

/// Score geometry is shared by the painter and boundary tests.
class ScrollingScoreGeometry {
  const ScrollingScoreGeometry(
    this.size, {
    this.minStep = 0,
    this.maxStep = 10,
    this.ticksPerBeat = 2,
  });
  final int minStep, maxStep, ticksPerBeat;
  final Size size;
  double get cursorX => (size.width * .22).clamp(76.0, 128.0);
  double get pixelsPerTick =>
      (size.width / 14).clamp(32.0, 56.0) * 2 / ticksPerBeat;
  // Treble staff, bottom to top: E4 G4 B4 D5 F5. Keys are C4–G4.
  double get staffGap => math.min(
    ((size.height - 40) / 7).clamp(10.0, 28.0),
    (size.height - 48) * 2 / (maxStep - minStep + 2),
  );
  double get staffTop => pitchY(10);
  double get staffBottom => staffTop + 4 * staffGap;
  double pitchY(int key) =>
      (size.height - (maxStep - minStep) * staffGap / 2) / 2 +
      (maxStep - key) * staffGap / 2;
  Rect noteRect(PieceNote note, double positionTick) => Rect.fromLTWH(
    cursorX + (note.startTick - positionTick) * pixelsPerTick,
    pitchY(note.key) - noteHeight / 2,
    note.ticks * pixelsPerTick,
    noteHeight,
  );
  double get noteHeight => (staffGap * 1.0).clamp(18.0, 34.0);
}

class ScrollingScore extends StatefulWidget {
  const ScrollingScore({
    super.key,
    required this.player,
    required this.frames,
    required this.chinese,
    this.demonstrating = false,
  });
  final ScrollingPiecePlayer player;
  final Listenable frames;
  final bool chinese;
  final bool demonstrating;
  @override
  State<ScrollingScore> createState() => _ScrollingScoreState();
}

class _ScrollingScoreState extends State<ScrollingScore> {
  final cache = ScrollingScoreCache();
  ScrollingPiecePlayer get player => widget.player;
  bool get chinese => widget.chinese;
  @override
  void dispose() {
    cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: chinese ? '移动音符与演奏线' : 'Scrolling notes and play line',
    value: player.targetKey == null
        ? ''
        : (chinese
              ? '${player.piece.keyLabel(player.targetKey!)} 号键，${player.piece.notes[player.currentIndex!].beats} 拍'
              : 'Key ${player.piece.keyLabel(player.targetKey!)}, ${player.piece.notes[player.currentIndex!].beats} beats'),
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('scrolling-score'),
        painter: ScrollingScorePainter(
          player,
          context.qin,
          widget.frames,
          cache: cache,
          demonstrating: widget.demonstrating,
          textScaler: musicTextScalerOf(context),
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// Layout and native paragraph resources survive note-boundary widget rebuilds.
/// A moving frame only translates precomputed rectangles and paints paragraphs.
class ScrollingScoreCache {
  PianoPiece? _piece;
  QinPalette? _palette;
  Size? _size;
  TextScaler? _textScaler;
  late ScrollingScoreGeometry geometry;
  List<Rect> rectangles = const [];
  List<String> labels = const [];
  List<Color> fills = const [],
      heldFills = const [],
      pastFills = const [],
      inks = const [],
      pastInks = const [],
      edges = const [];
  final _text = <(String, Color), ScoreNoteLabel>{};
  ui.Picture? staff, cursor;
  int layoutBuilds = 0, paragraphLayouts = 0;

  ScoreNoteLabel label(String value, Color color) =>
      _text.putIfAbsent((value, color), () {
        paragraphLayouts++;
        return ScoreNoteLabel(
          value,
          TextStyle(
            fontSize: math.min(24, geometry.noteHeight * .82),
            height: 1,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          scaler: _textScaler ?? TextScaler.noScaling,
        );
      });

  void prepare(
    Size size,
    PianoPiece piece,
    QinPalette palette, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (_size == size &&
        identical(_piece, piece) &&
        identical(_palette, palette) &&
        _textScaler == textScaler) {
      return;
    }
    dispose();
    _size = size;
    _piece = piece;
    _palette = palette;
    _textScaler = textScaler;
    layoutBuilds++;
    final steps = [for (var i = 0; i < piece.keyCount; i++) piece.keyStep(i)];
    final g = geometry = ScrollingScoreGeometry(
      size,
      minStep: math.min(0, steps.reduce(math.min)),
      maxStep: math.max(10, steps.reduce(math.max)),
      ticksPerBeat: piece.ticksPerBeat,
    );
    rectangles = [
      for (final n in piece.notes)
        g.noteRect(
          PieceNote(n.isRest ? 4 : piece.keyStep(n.key), n.ticks, n.startTick),
          0,
        ),
    ];
    labels = [
      for (final n in piece.notes) n.isRest ? '0' : piece.keyLabel(n.key),
    ];
    fills = [
      for (final n in piece.notes)
        n.isRest ? palette.soft : NoteColors.degree(piece.keyStep(n.key)).fill,
    ];
    heldFills = [
      for (final n in piece.notes)
        n.isRest
            ? palette.soft
            : NoteColors.degree(piece.keyStep(n.key)).pressed,
    ];
    inks = [
      for (final n in piece.notes)
        palette.highContrast || n.isRest
            ? palette.ink
            : NoteColors.degree(piece.keyStep(n.key)).ink,
    ];
    edges = [
      for (final n in piece.notes)
        palette.highContrast || n.isRest
            ? palette.edge
            : NoteColors.degree(piece.keyStep(n.key)).ink
                  .withValues(alpha: .65),
    ];
    pastFills = [
      for (final fill in fills) Color.lerp(fill, palette.background, .6)!,
    ];
    pastInks = [for (final ink in inks) Color.lerp(ink, palette.muted, .25)!];
    for (var i = 0; i < labels.length; i++) {
      label(labels[i], inks[i]);
      label(labels[i], pastInks[i]);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..strokeWidth = 1
      ..color = palette.line;
    for (var line = 0; line < 5; line++) {
      final y = g.staffTop + line * g.staffGap;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final clef = TextPainter(
      text: TextSpan(
        text: '𝄞',
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: 100,
          color: palette.muted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var bounds = Offset.zero & clef.size;
    for (final box in clef.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 2),
    )) {
      bounds = bounds.expandToInclude(box.toRect());
    }
    bounds = bounds.inflate(8);
    final area = Rect.fromLTRB(4, 12, 52, size.height - 12);
    final scale = math.min(
      area.width / bounds.width,
      area.height / bounds.height,
    );
    final top = (g.pitchY(4) - bounds.height * scale * .53)
        .clamp(
          area.top,
          math.max(area.top, area.bottom - bounds.height * scale),
        )
        .toDouble();
    canvas.save();
    canvas.translate(area.center.dx - bounds.width * scale / 2, top);
    canvas.scale(scale, scale);
    canvas.translate(-bounds.left, -bounds.top);
    clef.paint(canvas, Offset.zero);
    canvas.restore();
    staff = recorder.endRecording();
    clef.dispose();
    final cueRecorder = ui.PictureRecorder();
    final cue = Canvas(cueRecorder);
    paint.color = palette.primary;
    cue.drawRect(
      Rect.fromLTRB(g.cursorX - 2, 18, g.cursorX + 2, size.height - 12),
      paint,
    );
    cue.drawPath(
      Path()
        ..moveTo(g.cursorX - 7, 12)
        ..lineTo(g.cursorX + 7, 12)
        ..lineTo(g.cursorX, 21)
        ..close(),
      paint,
    );
    cursor = cueRecorder.endRecording();
  }

  void dispose() {
    for (final p in _text.values) {
      p.dispose();
    }
    _text.clear();
    staff?.dispose();
    cursor?.dispose();
    staff = cursor = null;
    _size = null;
    _piece = null;
    _palette = null;
    _textScaler = null;
  }
}

class ScrollingScorePainter extends CustomPainter {
  ScrollingScorePainter(
    this.player,
    this.palette,
    Listenable frames, {
    required this.cache,
    this.demonstrating = false,
    this.textScaler,
  }) : super(repaint: frames);
  final ScrollingPiecePlayer player;
  final QinPalette palette;
  final bool demonstrating;
  final TextScaler? textScaler;
  final ScrollingScoreCache cache;
  @override
  void paint(Canvas canvas, Size size) {
    cache.prepare(
      size,
      player.piece,
      palette,
      textScaler: textScaler ?? TextScaler.noScaling,
    );
    final g = cache.geometry;
    final position = player.positionTick;
    final scroll = position * g.pixelsPerTick;
    final currentIndex = player.currentIndex;
    final targetPressed = player.targetPressed;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..strokeWidth = 1
      ..color = palette.line;
    canvas.drawPicture(cache.staff!);
    for (
      var tick = player.piece.pickupTicks;
      tick <= player.piece.ticks;
      tick += player.piece.barTicks
    ) {
      final x = g.cursorX + tick * g.pixelsPerTick - scroll;
      if (x < 0 || x > size.width) continue;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), paint);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(56, 0, size.width, size.height));
    canvas.translate(-scroll, 0);
    for (var i = 0; i < player.piece.notes.length; i++) {
      final note = player.piece.notes[i];
      final r = cache.rectangles[i];
      if (r.right - scroll < 56) continue;
      if (r.left - scroll > size.width) break;
      final current = i == currentIndex;
      final held = current && !note.isRest && (demonstrating || targetPressed);
      final past = note.endTick <= position;
      final rounded = RRect.fromRectAndRadius(r, const Radius.circular(5));
      paint
        ..style = PaintingStyle.fill
        ..color = held
            ? cache.heldFills[i]
            : past
            ? cache.pastFills[i]
            : cache.fills[i];
      canvas.drawRRect(rounded, paint);
      // The played portion is part of the note itself, never a second timer bar.
      if (current && !held) {
        canvas.save();
        canvas.clipRRect(rounded);
        paint.color = cache.inks[i].withValues(alpha: .16);
        canvas.drawRect(
          Rect.fromLTRB(r.left, r.top, g.cursorX + scroll, r.bottom),
          paint,
        );
        canvas.restore();
      }
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = current ? 2.5 : 1.5
        ..color = current
            ? cache.inks[i]
            : past
            ? cache.pastInks[i]
            : cache.edges[i];
      canvas.drawRRect(rounded.deflate(.75), paint);
      paint.style = PaintingStyle.fill;
      final text = cache.label(
        cache.labels[i],
        past ? cache.pastInks[i] : cache.inks[i],
      );
      final left = r.left + math.min(8, r.width * .12);
      text.paintIn(
        canvas,
        Rect.fromLTRB(left, r.top + 1, r.right - 1, r.bottom - 1),
      );
    }
    canvas.restore();
    canvas.drawPicture(cache.cursor!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ScrollingScorePainter oldDelegate) => true;
}
