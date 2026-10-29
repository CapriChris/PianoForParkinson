import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/rhythm_timeline.dart';

import '../domain/responsive_controls_test.dart' show responsive, advanceTo;
import '../domain/task_engine_test.dart' show ready;

void main() {
  for (final zh in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'S2 prep label and matching demo/playing progress $zh $scale',
        (tester) async {
          tester.view.physicalSize = const Size(640, 360);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final c = ManualClock(), e = responsive(c, 'S2_RHYTHM');
          c.now = 300000;
          e.tick();
          Future<void> render() async {
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: RhythmTimeline(task: e, chinese: zh),
                  ),
                ),
              ),
            );
            await tester.pump();
          }

          await render();
          expect(
            find.text(zh ? '演示 · 预备拍 1 / 4' : 'Demo count in 1 / 4'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            0,
          );
          while (e.phase != 'demo') {
            c.now += 20000;
            e.tick();
          }
          advanceTo(e, c, c.now + 2250000);
          await render();
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            1.5 / 8,
          );
          ready(e, c);
          advanceTo(e, c, e.base + e.scheduledBeatUs + 2250000);
          await render();
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            1.5 / 8,
          );
          expect(e.soundingNoteIndex, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
