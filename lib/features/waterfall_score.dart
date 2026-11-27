import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/piece_timing.dart';
import '../domain/scrolling_piece.dart';
import '../ui/note_colors.dart';
import '../ui/qin_theme.dart';

class WaterfallScore extends StatelessWidget {
  const WaterfallScore({
    super.key,
    required this.player,
    required this.frames,
    this.chinese = true,
    this.demonstratingNotes = const {},
    this.keyOverlap = 0,
    this.showCues = true,
  });
  final ScrollingPiecePlayer player;
  final Listenable frames;
  final bool chinese;
  final double keyOverlap;
  final bool showCues;
  final Set<int> demonstratingNotes;

  @override
  Widget build(BuildContext context) => Semantics(
    label: chinese
        ? '音符从上向下落到对应琴键，长条长度表示按住时长'
        : 'Notes fall onto their keys; bar length shows hold duration',
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('waterfall-score'),
        painter: WaterfallPainter(
          player,
          frames,
          demonstratingNotes: demonstratingNotes,
          keyOverlap: keyOverlap,
          showCues: showCues,
          edge: context.qin.edge,
          reducedMotion: MediaQuery.disableAnimationsOf(context),
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// Key recesses are drawn once below the shared cue layer.
class WaterfallKeyBases extends StatelessWidget {
  const WaterfallKeyBases({
    super.key,
    required this.count,
    required this.player,
    required this.frames,
    this.showCues = true,
  });
  final ScrollingPiecePlayer player;
  final Listenable frames;
  final bool showCues;
  final int count;
  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: _CueRecessClipper(player, frames, showCues: showCues),
    child: Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(context.qin.disabled, context.qin.edge, .42),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: context.qin.ink.withValues(alpha: .08),
                    offset: const Offset(0, 3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ],
    ),
  );
}

/// A contacting cue hides the upper recess, independently of press judgement.
class _CueRecessClipper extends CustomClipper<Path> {
  _CueRecessClipper(this.player, Listenable frames, {required this.showCues})
    : super(reclip: frames);
  final ScrollingPiecePlayer player;
  final bool showCues;
  @override
  Path getClip(Size size) {
    var result = Path()
      ..addRect(Rect.fromLTRB(-8, -8, size.width + 8, size.height + 8));
    if (!showCues || player.mode == ScrollPieceMode.ready) return result;
    final width = WaterfallPainter.laneWidth(size.width, player.piece.keyCount);
    final speed = PieceTiming.pixelsPerBeat * player.tempo / 60000000;
    final upperHalf = Path()
      ..addRect(Rect.fromLTRB(-8, -8, size.width + 8, size.height / 2));
    for (var i = 0; i < player.piece.notes.length; i++) {
      final note = player.piece.notes[i];
      if (note.isRest) continue;
      final bottom = (player.elapsedUs - player.atTick(note.startTick)) * speed;
      final top = (player.elapsedUs - player.noteEndUs(i)) * speed;
      if (bottom < 0 || top >= size.height / 2) continue;
      final x = note.key * (width + 8);
      final cue = Path()
        ..addRect(Rect.fromLTRB(x, -8, x + width, size.height / 2));
      result = Path.combine(
        PathOperation.difference,
        result,
        Path.combine(PathOperation.intersect, cue, upperHalf),
      );
    }
    return result;
  }

  @override
  bool shouldReclip(_CueRecessClipper old) =>
      old.player != player || old.showCues != showCues;
}

class WaterfallPainter extends CustomPainter {
  WaterfallPainter(
    this.player,
    Listenable frames, {
    this.demonstratingNotes = const {},
    this.keyOverlap = 0,
    this.showCues = true,
    required this.edge,
    required this.reducedMotion,
  }) : super(repaint: frames);
  final ScrollingPiecePlayer player;
  final Color edge;
  final double keyOverlap;
  final bool showCues;
  final Set<int> demonstratingNotes;
  final bool reducedMotion;

  static double laneWidth(double width, int count) =>
      (width - (count - 1) * 8) / count;

  @override
  void paint(Canvas canvas, Size size) {
    // Negative score time is the approach to the first note. Only the separate
    // count-in hides cues; hiding the approach makes them pop onto the keys.
    if (!showCues || player.mode == ScrollPieceMode.ready) {
      return;
    }
    final contactY = size.height - keyOverlap;
    final piece = player.piece;
    final width = laneWidth(size.width, piece.keyCount);
    final speed = PieceTiming.pixelsPerBeat * player.tempo / 60000000;
    final paint = Paint();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var i = 0; i < piece.notes.length; i++) {
      final note = piece.notes[i];
      if (note.isRest) continue;
      final start = player.atTick(note.startTick);
      final end = player.noteEndUs(i);
      final bottom = contactY + (player.elapsedUs - start) * speed;
      final top = contactY + (player.elapsedUs - end) * speed;
      if (bottom < 0 || top >= size.height) continue;
      final color = NoteColors.degree(piece.keyStep(note.key) % 7).fill;
      final contact = player.elapsedUs >= start;
      final held = player.holdingNote(i) || demonstratingNotes.contains(i);
      final opacity = held
          ? 1.0
          : contact
          ? .7
          : .4;
      final x = note.key * (width + 8);
      final strong = Color.lerp(color, Colors.black, .22)!;
      paint.color = color.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, top, x + width, bottom),
          const Radius.circular(8),
        ),
        paint,
      );
      if (contact &&
          held &&
          !reducedMotion &&
          player.mode == ScrollPieceMode.running &&
          !player.waitingForKey) {
        _particles(canvas, size, x + width / 2, width, strong, contactY);
      }
    }
    canvas.restore();
  }

  void _particles(
    Canvas canvas,
    Size size,
    double center,
    double width,
    Color color,
    double contactY,
  ) {
    // Particle lifetime uses real time, independently of musical tempo.
    const lifetime = 420000;
    final now = player.clock.now;
    final batch = now ~/ 50000;
    final paint = Paint();
    for (var age = 0; age < 8; age++) {
      final seed = batch - age;
      final elapsed = (now - seed * 50000) / lifetime;
      if (elapsed < 0 || elapsed >= 1) continue;
      for (var n = 0; n < 5; n++) {
        final random = math.Random(seed * 31 + n * 997 + center.round());
        final offset = (random.nextDouble() - .5) * width * .7;
        final direction = random.nextDouble() * math.pi;
        final distance = elapsed * (32 + random.nextDouble() * 50);
        paint.color = color.withValues(alpha: (1 - elapsed));
        canvas.drawCircle(
          Offset(
            center + offset + math.cos(direction) * distance,
            contactY - 2 - math.sin(direction) * distance,
          ),
          (1 - elapsed) * (2.5 + random.nextDouble() * 2.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(WaterfallPainter oldDelegate) =>
      oldDelegate.player != player ||
      oldDelegate.demonstratingNotes != demonstratingNotes ||
      oldDelegate.keyOverlap != keyOverlap ||
      oldDelegate.showCues != showCues ||
      oldDelegate.edge != edge ||
      oldDelegate.reducedMotion != reducedMotion;
}
