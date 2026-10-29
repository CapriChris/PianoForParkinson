import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/rhythm_timeline.dart';
import 'package:piano_practice/features/training_page.dart';

import '../domain/alternate_test.dart' show alternate;
import '../domain/responsive_controls_test.dart' show advanceTo;
import '../domain/task_engine_test.dart' show ready;
import 'cognitive_pages_test.dart' show mocks;

class AlternateController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    engine = alternate(clock)..layoutSnapshot = keyboardLayout;
    content.config = engine!.config;
    layout = keyboardLayout;
    ready(engine!, clock);
    notifyListeners();
  }
}

void main() {
  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    for (final locale in ['zh-Hans', 'en']) {
      testWidgets(
        'M1 instruction preview has exactly two keys ${size.width} $locale',
        (tester) async {
          final c = AlternateController();
          mocks(tester, size, locale, 1, c);
          await tester.pumpWidget(
            MaterialApp(
              home: InstructionPage(c: c, taskId: 'M1_ALTERNATE'),
            ),
          );
          final button = find.text(locale == 'en' ? 'Try the keys' : '试按琴键');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(
            tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).count,
            2,
          );
          expect(
            tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).active,
            {0, 1},
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
  for (final samples in [0, 9, 10]) {
    testWidgets('M1 interval CV sample threshold $samples', (tester) async {
      final c = AlternateController();
      mocks(tester, const Size(640, 360), 'en', 1, c);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetricTiming(
              c: c,
              label: 'Consecutive hit interval',
              value: timingStatistics(List.filled(samples, 1500000)),
              showCv: true,
            ),
          ),
        ),
      );
      if (samples == 0) {
        expect(find.textContaining('no valid samples'), findsOneWidget);
        expect(find.textContaining('CV'), findsNothing);
      } else {
        expect(
          find.textContaining(
            samples < 10 ? 'CV needs at least 10' : 'CV 0.0%',
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  for (final size in [const Size(640, 360), const Size(914, 411)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'M1 spacious two keys, hold and pause ${size.width} $locale $scale',
          (tester) async {
            final c = AlternateController();
            mocks(tester, size, locale, scale, c);
            await tester.pumpWidget(PianoApp(controller: c));
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainingPage(c: c, taskId: 'M1_ALTERNATE'),
                  ),
                );
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            final e = c.engine!, clock = e.clock as ManualClock;
            final keyboard = find.byType(PianoKeyboard),
                guide = find.byType(KeyDurationGuide);
            final rect = tester.getRect(keyboard),
                guideRect = tester.getRect(guide);
            expect(tester.widget<PianoKeyboard>(keyboard).count, 2);
            expect(tester.widget<PianoKeyboard>(keyboard).active, {0, 1});
            expect(c.layout!['layout_id'], 'ALTERNATE_TWO_KEYS');
            expect(rect.width, lessThanOrEqualTo(520));
            expect(rect.center.dx, closeTo(size.width / 2, 1));
            expect(guideRect.left, rect.left);
            expect(guideRect.width, rect.width);
            expect(guideRect.bottom, lessThanOrEqualTo(rect.top));
            expect(find.byType(RhythmTimeline), findsOneWidget);
            advanceTo(e, clock, e.base + e.scheduledBeatUs);
            e.down(1, 0);
            clock.now += 200000;
            e.tick();
            c.notifyListeners();
            await tester.pump();
            expect(
              tester.widget<KeyDurationGuide>(guide).progress,
              closeTo(.5, .01),
            );
            expect(tester.widget<KeyDurationGuide>(guide).targetKey, 0);
            e.up(1);
            expect(e.durationTooShort, true);
            e.pause('USER');
            c.notifyListeners();
            await tester.pumpAndSettle();
            expect(tester.widget<KeyDurationGuide>(guide).targetKey, isNull);
            expect(tester.widget<PianoKeyboard>(keyboard).highlighted, isNull);
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('more-help')),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('replay-demo')),
                  )
                  .onPressed,
              isNotNull,
            );
            expect(tester.getRect(keyboard), rect);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
}
