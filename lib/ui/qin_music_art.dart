import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'qin_theme.dart';

/// Artwork is decorative; all meaningful text remains outside the image.
class QinArtwork extends StatelessWidget {
  const QinArtwork({super.key, required this.asset, this.height = 150});
  final String asset;
  final double height;
  @override
  Widget build(BuildContext context) {
    if (context.qin.highContrast) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.asset(
        'assets/ui_images/${asset.replaceAll('.png', '.webp')}',
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: height <= 100 ? 240 : 900,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

String? qinPieceImage(String id) {
  if (id.contains('frere')) return '02-two-tigers.png';
  if (id.contains('twinkle')) return '03-twinkle.png';
  if (id.contains('ode-to-joy')) return '04-ode-to-joy.png';
  if (id.contains('saints')) return '05-saints.png';
  if (id.contains('birthday')) return '06-happy-birthday.png';
  if (id.contains('sunshine')) return '07-sunshine.png';
  return null;
}

String qinPracticeImage(String id) => switch (id) {
  'G1_MEMORY' => '14-melody-memory.png',
  'G2_INHIBITION' => '15-play-and-wait.png',
  'G3_SWITCH' => '22-practice-rule-switch.png',
  'S1_GUIDED' => '23-practice-short-melody.png',
  'S2_RHYTHM' => '16-metronome.png',
  'M1_ALTERNATE' => '24-practice-alternating.png',
  'M2_DUAL_ZONE' => '20-practice-dual-zone-v2.png',
  _ => '13-open-score.png',
};

String? qinSongImage(String taskId, String songId) =>
    switch ((taskId, songId)) {
      ('S1_GUIDED', 'song-original-001') => '25-melody-beginning.png',
      ('S1_GUIDED', 'song-original-002') => '26-melody-rising-echo.png',
      ('S1_GUIDED', 'song-original-003') => '27-melody-gentle-fall.png',
      ('S2_RHYTHM', 'song-original-002') => '28-rhythm-rising-echo.png',
      ('S2_RHYTHM', 'song-original-003') => '29-rhythm-gentle-fall.png',
      _ => null,
    };

class QinWelcome extends StatelessWidget {
  const QinWelcome({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) {
    final showPhoto =
        !context.qin.highContrast &&
        (MediaQuery.sizeOf(context).width >= 600 ||
            MediaQuery.textScalerOf(context).scale(1) <= 1.5);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.qin.highContrast
            ? context.qin.surface
            : const Color(0xfff1eee3),
        border: Border.all(color: context.qin.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showPhoto) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/ui_images/01-home-piano.webp',
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                cacheWidth: 900,
                alignment: Alignment.center,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Original, quiet miniature scenes for the six pieces, with no text baked in.
class QinPieceArtwork extends StatelessWidget {
  const QinPieceArtwork({super.key, required this.id, this.size = 76});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: qinPieceImage(id) != null
          ? Image.asset(
              'assets/ui_images/${qinPieceImage(id)!.replaceAll('.png', '.webp')}',
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: 480,
              errorBuilder: (_, _, _) => CustomPaint(
                size: Size.square(size),
                painter: _PieceArtworkPainter(id),
              ),
            )
          : CustomPaint(
              size: Size.square(size),
              painter: _PieceArtworkPainter(id),
            ),
    ),
  );
}

class _PieceArtworkPainter extends CustomPainter {
  const _PieceArtworkPainter(this.id);
  final String id;
  void oval(Canvas c, Paint p, Color color, Rect rect) {
    p.color = color;
    c.drawOval(rect, p);
  }

  void circle(
    Canvas c,
    Paint p,
    Color color,
    double x,
    double y,
    double radius,
  ) {
    p.color = color;
    c.drawCircle(Offset(x, y), radius, p);
  }

  void rounded(Canvas c, Paint p, Color color, Rect rect, double radius) {
    p.color = color;
    c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), p);
  }

  void star(Canvas c, Paint p, double x, double y, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * .43;
      final point = Offset(x + math.cos(a) * r, y + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    p.color = color;
    c.drawPath(path..close(), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final p = Paint()..isAntiAlias = true;
    final dark = const Color(0xff34584d), cream = const Color(0xfffffaf0);
    final isTwinkle = id.contains('twinkle'),
        isTiger = id.contains('frere'),
        isSaints = id.contains('saints'),
        isBirthday = id.contains('birthday'),
        isSun = id.contains('sunshine');
    final bg = isTwinkle
        ? const Color(0xffd8e3e4)
        : isTiger
        ? const Color(0xfff1dfc5)
        : isSaints
        ? const Color(0xffe8e5d4)
        : isBirthday
        ? const Color(0xfff2dfd4)
        : isSun
        ? const Color(0xfff0e6bf)
        : const Color(0xffe5eadb);
    canvas.drawColor(bg, BlendMode.src);
    oval(
      canvas,
      p,
      Colors.white.withValues(alpha: .32),
      const Rect.fromLTWH(-18, -22, 110, 90),
    );
    if (isTwinkle) {
      circle(canvas, p, const Color(0xffe3b963), 44, 42, 22);
      circle(canvas, p, bg, 53, 34, 19);
      star(canvas, p, 73, 26, 6, cream);
      star(canvas, p, 68, 62, 8, const Color(0xffcc9a4b));
      star(canvas, p, 24, 68, 5, cream);
      circle(canvas, p, dark.withValues(alpha: .35), 18, 26, 2);
    } else if (isTiger) {
      for (final x in [32.0, 68.0]) {
        p.color = const Color(0xffb67c4d);
        canvas.drawPath(
          Path()
            ..moveTo(x - 17, 35)
            ..lineTo(x - 15, 18)
            ..lineTo(x - 2, 29)
            ..close(),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(x + 17, 35)
            ..lineTo(x + 15, 18)
            ..lineTo(x + 2, 29)
            ..close(),
          p,
        );
        circle(canvas, p, const Color(0xffdfab70), x, 47, 20);
        oval(
          canvas,
          p,
          cream,
          Rect.fromCenter(center: Offset(x, 54), width: 23, height: 14),
        );
        circle(canvas, p, dark, x - 7, 44, 1.8);
        circle(canvas, p, dark, x + 7, 44, 1.8);
        circle(canvas, p, dark, x, 51, 1.8);
        p
          ..color = const Color(0xffa5714c)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(x - 4, 31), Offset(x - 2, 36), p);
        canvas.drawLine(Offset(x + 4, 31), Offset(x + 2, 36), p);
      }
      rounded(
        canvas,
        p,
        dark.withValues(alpha: .16),
        const Rect.fromLTWH(16, 74, 68, 5),
        3,
      );
    } else if (isSaints) {
      p
        ..color = const Color(0xffba8b47)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(24, 57)
          ..lineTo(48, 57)
          ..quadraticBezierTo(60, 57, 60, 45)
          ..lineTo(60, 35),
        p,
      );
      p.style = PaintingStyle.fill;
      p.color = const Color(0xffd3a956);
      canvas.drawPath(
        Path()
          ..moveTo(56, 36)
          ..lineTo(42, 24)
          ..quadraticBezierTo(61, 27, 79, 16)
          ..lineTo(68, 37)
          ..close(),
        p,
      );
      oval(
        canvas,
        p,
        const Color(0xffaa7937),
        const Rect.fromLTWH(42, 20, 38, 10),
      );
      rounded(canvas, p, dark, const Rect.fromLTWH(22, 53, 9, 8), 3);
      star(canvas, p, 78, 63, 6, const Color(0xffd3a956));
      star(canvas, p, 24, 25, 4, cream);
    } else if (isBirthday) {
      oval(
        canvas,
        p,
        const Color(0xffb4c1ae),
        const Rect.fromLTWH(15, 75, 70, 12),
      );
      rounded(
        canvas,
        p,
        const Color(0xffc97964),
        const Rect.fromLTWH(24, 48, 52, 30),
        7,
      );
      rounded(canvas, p, cream, const Rect.fromLTWH(24, 45, 52, 12), 6);
      for (final x in [36.0, 50.0, 64.0]) {
        rounded(canvas, p, dark, Rect.fromLTWH(x - 2, 28, 4, 19), 2);
        oval(
          canvas,
          p,
          const Color(0xffdda751),
          Rect.fromLTWH(x - 3, 20, 6, 9),
        );
      }
      star(canvas, p, 17, 28, 4, cream);
      star(canvas, p, 82, 35, 5, const Color(0xffd7a555));
    } else if (isSun) {
      circle(canvas, p, const Color(0xffdfa950), 50, 37, 20);
      p
        ..color = const Color(0xffdda751)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        canvas.drawLine(
          Offset(50 + math.cos(a) * 27, 37 + math.sin(a) * 27),
          Offset(50 + math.cos(a) * 33, 37 + math.sin(a) * 33),
          p,
        );
      }
      p.color = const Color(0xffa9b99b);
      canvas.drawPath(
        Path()
          ..moveTo(0, 79)
          ..quadraticBezierTo(26, 57, 53, 80)
          ..quadraticBezierTo(77, 59, 100, 74)
          ..lineTo(100, 100)
          ..lineTo(0, 100)
          ..close(),
        p,
      );
      p.color = const Color(0xff728f75);
      canvas.drawPath(
        Path()
          ..moveTo(0, 88)
          ..quadraticBezierTo(35, 69, 65, 88)
          ..quadraticBezierTo(80, 77, 100, 86)
          ..lineTo(100, 100)
          ..lineTo(0, 100)
          ..close(),
        p,
      );
    } else {
      circle(canvas, p, const Color(0xffe4bd72), 70, 27, 13);
      star(canvas, p, 23, 26, 5, cream);
      rounded(canvas, p, dark, const Rect.fromLTWH(16, 48, 68, 32), 7);
      rounded(canvas, p, cream, const Rect.fromLTWH(20, 53, 60, 23), 3);
      p
        ..color = const Color(0xffb4c0ad)
        ..strokeWidth = 1;
      for (var x = 30.0; x < 80; x += 10) {
        canvas.drawLine(Offset(x, 53), Offset(x, 76), p);
      }
      for (final x in [27.0, 37.0, 57.0, 67.0]) {
        rounded(canvas, p, dark, Rect.fromLTWH(x, 53, 6, 12), 1);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PieceArtworkPainter oldDelegate) => oldDelegate.id != id;
}
