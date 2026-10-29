import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/rhythm_timeline.dart';
import 'package:piano_practice/features/response_countdown.dart';

import '../domain/responsive_controls_test.dart'
    show responsive, toGo, advanceTo;
import '../domain/task_engine_test.dart' show ready;
import 'cognitive_pages_test.dart' show mocks;

class ResponsiveController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final time = ManualClock();
    engine = responsive(time, taskId);
    engine!.layoutSnapshot = keyboardLayout;
    layout = keyboardLayout;
    if (taskId == 'G2_INHIBITION') {
      toGo(engine!, time);
    } else {
      ready(engine!, time);
    }
    notifyListeners();
  }
}

void main() {
  for (final task in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'S1_GUIDED',
    'S2_RHYTHM',
  ]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('responsive controls $task $locale $scale', (tester) async {
          final c = ResponsiveController();
          mocks(tester, const Size(640, 360), locale, scale, c);
          await tester.pumpWidget(PianoApp(controller: c));
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainingPage(c: c, taskId: task),
                ),
              );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          final e = c.engine!, time = e.clock as ManualClock;
          final keyboard = find.byType(PianoKeyboard);
          final rect = tester.getRect(keyboard);
          expect(
            find.byType(ResponseCountdown),
            task.startsWith('G') ? findsOneWidget : findsNothing,
          );
          expect(find.textContaining('请松开琴键'), findsNothing);
          expect(find.textContaining('0.4'), findsNothing);
          if (task == 'S2_RHYTHM') {
            advanceTo(e, time, e.base + e.scheduledBeatUs);
            c.notifyListeners();
            await tester.pump();
            final painter =
                tester
                        .widget<CustomPaint>(
                          find
                              .descendant(
                                of: find.byType(RhythmTimeline),
                                matching: find.byType(CustomPaint),
                              )
                              .first,
                        )
                        .painter
                    as dynamic;
            expect(painter.position, closeTo(0, 1e-9));
            expect(find.textContaining('现在弹奏'), findsNothing);
            expect(find.textContaining('准备'), findsNothing);
          } else {
            e.down(1, e.expected.first);
            time.now += 100000;
            e.up(1);
            time.now += 1300000;
            e.tick();
            c.notifyListeners();
            await tester.pump();
            expect(e.durationTooShort, true);
            expect(
              tester.widget<PianoKeyboard>(keyboard).locked,
              task == 'G2_INHIBITION' || task == 'G3_SWITCH',
            );
            expect(
              find.textContaining(locale == 'en' ? 'Too short' : '时值不足'),
              findsOneWidget,
            );
            expect(tester.getRect(keyboard), rect);
          }
          e.pause('USER');
          c.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
                .targetKey,
            isNull,
          );
          expect(tester.widget<PianoKeyboard>(keyboard).highlighted, isNull);
          expect(
            tester
                    .widget<OutlinedButton>(
                      find.byKey(const ValueKey('replay-demo')),
                    )
                    .onPressed ==
                null,
            task == 'G3_SWITCH',
          );
          expect(
            tester
                    .widget<OutlinedButton>(
                      find.byKey(const ValueKey('more-help')),
                    )
                    .onPressed ==
                null,
            task != 'G1_MEMORY' && task != 'G3_SWITCH',
          );
          expect(tester.getRect(keyboard), rect);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        });
      }
    }
  }
}
