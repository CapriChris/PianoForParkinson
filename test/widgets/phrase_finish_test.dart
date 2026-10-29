import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/rhythm_timeline.dart';

import '../domain/responsive_controls_test.dart' show responsive, advanceTo;
import '../domain/task_engine_test.dart' show ready;
import 'cognitive_pages_test.dart' show mocks;

class CounterController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    engine = responsive(clock, taskId)..layoutSnapshot = keyboardLayout;
    content.config = engine!.config;
    layout = keyboardLayout;
    ready(engine!, clock);
    notifyListeners();
  }
}

Future<void> open(
  WidgetTester tester,
  CounterController c,
  String task,
  String locale, {
  Size size = const Size(800, 400),
}) async {
  mocks(tester, size, locale, 1, c);
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
}

void main() {
  for (final locale in ['zh-Hans', 'en']) {
    for (final task in [
      'G1_MEMORY',
      'G2_INHIBITION',
      'G3_SWITCH',
      'S1_GUIDED',
      'S2_RHYTHM',
      'M1_ALTERNATE',
    ]) {
      testWidgets(
        '$task $locale shows the first current item, not zero completed',
        (tester) async {
          final c = CounterController();
          await open(tester, c, task, locale);
          expect(c.engine!.completed, 0);
          expect(
            find.textContaining(
              RegExp(
                r'· 1\s*/\s*'
                '${c.engine!.planned}',
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
    for (final task in ['S2_RHYTHM', 'M1_ALTERNATE']) {
      testWidgets('$task $locale counter fits a short phone landscape', (
        tester,
      ) async {
        final c = CounterController();
        await open(tester, c, task, locale, size: const Size(800, 360));
        final counter = find.textContaining('1/${c.engine!.planned}');
        final counterRect = tester.getRect(counter);
        final keyboardRect = tester.getRect(find.byType(PianoKeyboard));
        expect(counterRect.top, greaterThanOrEqualTo(0));
        expect(counterRect.bottom, lessThanOrEqualTo(keyboardRect.top));
        expect(counterRect.right, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      });
      testWidgets(
        '$task $locale keeps the timeline visible through final beat and pause',
        (tester) async {
          final c = CounterController();
          await open(tester, c, task, locale);
          final e = c.engine!, clock = e.clock as ManualClock;
          for (var i = 0; i < e.trialCount; i++) {
            if (i > 0) ready(e, clock);
            advanceTo(e, clock, e.base + e.scheduledBeatUs + e.beatAfterUs);
          }
          c.notifyListeners();
          await tester.pump();
          final next = find.text(locale == 'en' ? 'Next block' : '开始下一组');
          expect(find.byType(RhythmTimeline), findsOneWidget);
          expect(next, findsNothing);
          expect(
            tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
            true,
          );
          expect(
            find.textContaining('${e.trialCount}/${e.planned}'),
            findsOneWidget,
          );
          final end = e.base + e.phraseEndUs;
          e.pause('USER');
          c.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const ValueKey('replay-demo')),
                )
                .onPressed,
            isNull,
          );
          clock.now += 3000000;
          e.resume();
          advanceTo(e, clock, end + 3000000 - 1);
          c.notifyListeners();
          await tester.pump();
          expect(next, findsNothing);
          advanceTo(e, clock, end + 3000000);
          c.notifyListeners();
          await tester.pump();
          expect(next, findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
}
