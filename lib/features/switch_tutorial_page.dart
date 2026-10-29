import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/text_scale.dart';
import '../ui/qin_components.dart';
import '../app/page_title.dart';
import 'cognitive_cue.dart';
import 'keyboard.dart';
import 'training_page.dart';
import 'spoken_text.dart';

class SwitchTutorialPage extends StatefulWidget {
  const SwitchTutorialPage({super.key, required this.c});
  final AppController c;
  @override
  State<SwitchTutorialPage> createState() => _SwitchTutorialPageState();
}

class _SwitchTutorialPageState extends State<SwitchTutorialPage> {
  static const examples = [
    (position: 0, shape: 1, target: 0),
    (position: 2, shape: 0, target: 2),
    (position: 0, shape: 1, target: 1),
    (position: 1, shape: 2, target: 2),
  ];
  int index = 0;
  bool correct = false;
  final held = <int>{};
  String? feedback;
  AppController get c => widget.c;
  Future<void> start() async {
    await c.stopPreview();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TrainingPage(c: c, taskId: 'G3_SWITCH'),
        ),
      );
    }
  }

  Widget feedbackSpace() => LayoutBuilder(
    builder: (context, constraints) {
      final messages = [
        c.text('对应正确，可以继续。', 'That matches. You can continue.'),
        c.text('再看一下当前规则，可以再试。', 'Check the current rule and try again.'),
      ];
      var messageHeight = 24.0;
      for (final message in messages) {
        final painter = TextPainter(
          text: TextSpan(
            text: message,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: math.max(1, constraints.maxWidth - 72));
        messageHeight = math.max(messageHeight, painter.height);
        painter.dispose();
      }
      return SizedBox(
        key: const ValueKey('switch-feedback-reserve'),
        height: messageHeight + 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: feedback == null
              ? null
              : Align(
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    liveRegion: true,
                    child: QinStatus(
                      text: feedback!,
                      tone: correct ? QinTone.success : QinTone.warning,
                    ),
                  ),
                ),
        ),
      );
    },
  );

  @override
  void dispose() {
    unawaited(c.stopPreview());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: PageTitle(c.text('试玩', 'Try both rules'))),
    body: SafeArea(
      child: QinPageList(
        children: [
          QinStepProgress(
            current: index < examples.length ? index + 1 : examples.length,
            total: examples.length,
            label: c.text('规则试玩', 'Rule examples'),
          ),
          const SizedBox(height: 20),
          if (index < examples.length) ...[
            Text(
              c.text(
                '${index + 1} / 4 · ${index < 2 ? '规则 A：按位置' : '规则 B：按图形'}',
                '${index + 1} / 4 · ${index < 2 ? 'Rule A: match position' : 'Rule B: match shape'}',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Center(
              child: SignalSlots(
                position: examples[index].position,
                shape: examples[index].shape,
              ),
            ),
            const SizedBox(height: 16),
            SpokenText(
              c: c,
              circularAligned: true,
              text: index < 2
                  ? c.text(
                      '看图形在哪个位置，按同位置的琴键，不管它是什么图形。',
                      'Press the key in the same position, regardless of the shape.',
                    )
                  : c.text(
                      '看它是什么图形，按带有相同图形的琴键，不管它在哪个位置。',
                      'Press the key with the matching shape, regardless of its position.',
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 136,
              child: PianoKeyboard(
                interruptions: c.previewInterruptions,
                onInterrupted: () => setState(() {
                  held.clear();
                  correct = false;
                  feedback = null;
                }),
                count: 3,
                active: const {0, 1, 2},
                showShapes: true,
                textScale: (musicTextScalerOf(context).scale(1) * 1000).round(),
                onDown: (p, k, d, xy) {
                  setState(() => held.add(p));
                  if (k != null) c.preview(k, true, pointer: p);
                },
                onUp: (p, k, cancel, xy) {
                  held.remove(p);
                  if (k != null) c.preview(k, false, pointer: p);
                  if (!cancel && k != null && index < examples.length) {
                    setState(() {
                      correct = k == examples[index].target;
                      feedback = correct
                          ? c.text(
                              '对应正确，可以继续。',
                              'That matches. You can continue.',
                            )
                          : c.text(
                              '再看一下当前规则，可以再试。',
                              'Check the current rule and try again.',
                            );
                    });
                  } else {
                    setState(() {});
                  }
                },
              ),
            ),
            feedbackSpace(),
            FilledButton(
              onPressed: correct && held.isEmpty
                  ? () => setState(() {
                      index++;
                      correct = false;
                      feedback = null;
                    })
                  : null,
              child: Text(c.text('下一个示例', 'Next example')),
            ),
          ] else ...[
            Text(
              c.text(
                '两种规则都试过了。正式练习时，当前规则会一直显示。',
                'You tried both rules. The current rule stays visible during practice.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: start,
              child: Text(c.text('开始正式练习', 'Start practice')),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {
                index = 0;
                feedback = null;
                correct = false;
              }),
              child: Text(c.text('再试一遍', 'Repeat examples')),
            ),
          ],
        ],
      ),
    ),
  );
}
