import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_components.dart';
import '../ui/qin_theme.dart';
import 'spoken_text.dart';

enum PracticeStepArt {
  listen,
  sequence,
  playSignal,
  wait,
  rules,
  target,
  beatListen,
  beatPlay,
  alternate,
  dualObserve,
  dualPress,
}

typedef PracticeStep = ({String zh, String en, PracticeStepArt art});

List<PracticeStep> practiceSteps(String taskId) => switch (taskId) {
  'G1_MEMORY' => [
    (
      zh: '听示范，记住亮键顺序',
      en: 'Listen and remember the lit keys',
      art: PracticeStepArt.listen,
    ),
    (zh: '按顺序弹奏', en: 'Play in the same order', art: PracticeStepArt.sequence),
  ],
  'G2_INHIBITION' => [
    (
      zh: '看到“弹奏”，按提示的琴键',
      en: 'For Play, press the indicated key',
      art: PracticeStepArt.playSignal,
    ),
    (zh: '看到“等待”，不按键', en: 'For Wait, do not press', art: PracticeStepArt.wait),
  ],
  'G3_SWITCH' => [
    (zh: '看清当前规则', en: 'Check the current rule', art: PracticeStepArt.rules),
    (zh: '按对应琴键', en: 'Press the matching key', art: PracticeStepArt.target),
  ],
  'S1_GUIDED' => [
    (zh: '听示范', en: 'Listen to the example', art: PracticeStepArt.listen),
    (
      zh: '按提示弹奏',
      en: 'Play following the prompts',
      art: PracticeStepArt.target,
    ),
  ],
  'S2_RHYTHM' => [
    (
      zh: '听示范，感受节拍',
      en: 'Listen and feel the beat',
      art: PracticeStepArt.beatListen,
    ),
    (zh: '跟着节拍弹奏', en: 'Play to the beat', art: PracticeStepArt.beatPlay),
  ],
  'M1_ALTERNATE' => [
    (zh: '听示范', en: 'Listen to the example', art: PracticeStepArt.listen),
    (
      zh: '跟着节拍交替弹奏',
      en: 'Alternate keys to the beat',
      art: PracticeStepArt.alternate,
    ),
  ],
  'M2_DUAL_ZONE' => [
    (
      zh: '看清左右两区的提示',
      en: 'Look at the cues on both sides',
      art: PracticeStepArt.dualObserve,
    ),
    (
      zh: '同时按下两边的琴键',
      en: 'Press both keys together',
      art: PracticeStepArt.dualPress,
    ),
  ],
  _ => const [],
};

class PracticeStepsPanel extends StatelessWidget {
  const PracticeStepsPanel({super.key, required this.c, required this.steps});
  final AppController c;
  final List<PracticeStep> steps;

  @override
  Widget build(BuildContext context) => QinPanel(
    soft: true,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpokenText(
          c: c,
          text: steps.map((step) => c.chinese ? step.zh : step.en).join('。'),
          circularAligned: true,
          actionOnly: true,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.qin.highContrast
                        ? context.qin.surface
                        : const Color(0xffdce9df),
                    border: context.qin.highContrast
                        ? Border.all(color: context.qin.ink)
                        : null,
                  ),
                  child: FittedBox(
                    child: Text(
                      '${i + 1}',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(color: context.qin.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: SizedBox(
                    width: 76,
                    height: 58,
                    child: CustomPaint(
                      painter: _PracticeStepPainter(
                        steps[i].art,
                        context.qin.primary,
                        context.qin.ink,
                        context.qin.highContrast,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.chinese ? steps[i].zh : steps[i].en,
                    key: ValueKey('practice-step-$i'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// Small vector diagrams: keys, a signal and a simple cue, without text baked in.
class _PracticeStepPainter extends CustomPainter {
  const _PracticeStepPainter(
    this.art,
    this.accent,
    this.ink,
    this.highContrast,
  );
  final PracticeStepArt art;
  final Color accent, ink;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 76, size.height / 58);
    final stroke = Paint()
      ..color = ink.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fill = Paint()
      ..color = highContrast ? Colors.white : const Color(0xfffffaf0);
    final highlight = Paint()
      ..color = highContrast ? Colors.black : const Color(0xffe6b455);
    final line = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round;
    final bold = Paint()..color = accent;
    final dual =
        art == PracticeStepArt.dualObserve || art == PracticeStepArt.dualPress;
    for (var i = 0; i < 4; i++) {
      final x = 6.0 + i * 16;
      final selected = dual ? i == 0 || i == 3 : i == 1;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 27, 15, 25),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, selected ? highlight : fill);
      canvas.drawRRect(rect, stroke);
    }
    void note(double x, double y) {
      canvas.drawOval(Rect.fromLTWH(x, y + 8, 6, 4), bold);
      canvas.drawLine(Offset(x + 5, y + 9), Offset(x + 5, y), line);
      canvas.drawLine(Offset(x + 5, y), Offset(x + 10, y + 2), line);
    }

    void arrow(double x, double y, bool reverse) {
      final direction = reverse ? -1.0 : 1.0;
      canvas.drawLine(Offset(x, y), Offset(x + 16 * direction, y), line);
      canvas.drawLine(
        Offset(x + 16 * direction, y),
        Offset(x + 12 * direction, y - 3),
        line,
      );
      canvas.drawLine(
        Offset(x + 16 * direction, y),
        Offset(x + 12 * direction, y + 3),
        line,
      );
    }

    switch (art) {
      case PracticeStepArt.listen:
        note(25, 5);
        note(43, 3);
      case PracticeStepArt.sequence:
        arrow(20, 13, false);
        arrow(40, 13, false);
      case PracticeStepArt.playSignal:
        canvas.drawPath(
          Path()
            ..moveTo(31, 3)
            ..lineTo(46, 12)
            ..lineTo(31, 21)
            ..close(),
          bold,
        );
      case PracticeStepArt.wait:
        canvas.drawCircle(const Offset(38, 13), 9, line);
        canvas.drawLine(const Offset(38, 8), const Offset(38, 13), line);
        canvas.drawLine(const Offset(38, 13), const Offset(42, 16), line);
      case PracticeStepArt.rules:
        canvas.drawPath(
          Path()
            ..moveTo(16, 20)
            ..lineTo(23, 5)
            ..lineTo(30, 20)
            ..close(),
          line,
        );
        canvas.drawCircle(const Offset(39, 13), 7, line);
        canvas.drawRect(const Rect.fromLTWH(51, 6, 14, 14), line);
      case PracticeStepArt.target:
        canvas.drawCircle(const Offset(29, 12), 7, line);
        canvas.drawLine(const Offset(29, 19), const Offset(29, 25), line);
      case PracticeStepArt.beatListen:
        note(18, 7);
        note(50, 7);
        canvas.drawLine(const Offset(38, 4), const Offset(32, 21), line);
        canvas.drawLine(const Offset(38, 4), const Offset(44, 21), line);
        canvas.drawLine(const Offset(32, 21), const Offset(44, 21), line);
      case PracticeStepArt.beatPlay:
        canvas.drawLine(const Offset(38, 4), const Offset(32, 20), line);
        canvas.drawLine(const Offset(38, 4), const Offset(44, 20), line);
        canvas.drawLine(const Offset(32, 20), const Offset(44, 20), line);
        canvas.drawCircle(const Offset(55, 14), 3, bold);
      case PracticeStepArt.alternate:
        arrow(18, 9, false);
        arrow(58, 19, true);
      case PracticeStepArt.dualObserve:
        canvas.drawCircle(const Offset(13, 13), 6, line);
        canvas.drawCircle(const Offset(61, 13), 6, line);
        canvas.drawLine(const Offset(13, 19), const Offset(13, 25), line);
        canvas.drawLine(const Offset(61, 19), const Offset(61, 25), line);
      case PracticeStepArt.dualPress:
        for (final x in [13.0, 61.0]) {
          canvas.drawLine(Offset(x, 6), Offset(x, 22), line);
          canvas.drawLine(Offset(x, 22), Offset(x - 4, 18), line);
          canvas.drawLine(Offset(x, 22), Offset(x + 4, 18), line);
        }
    }
    // Restore the incoming canvas for other widgets.
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PracticeStepPainter old) =>
      old.art != art ||
      old.accent != accent ||
      old.ink != ink ||
      old.highContrast != highContrast;
}
