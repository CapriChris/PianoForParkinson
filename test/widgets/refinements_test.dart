import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/rhythm_timeline.dart';
import 'package:piano_practice/features/training_page.dart';

import '../domain/hold_policy_test.dart' show held;
import '../domain/task_engine_test.dart' show ready;
import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

class CurrentController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    engine = held(clock, taskId);
    layout = keyboardLayout;
    engine!.layoutSnapshot = keyboardLayout;
    ready(engine!, clock);
    while (taskId == 'G2_INHIBITION' &&
        engine!.target['trial_type'] == 'NO_GO') {
      clock.now += engine!.responseWindowUs;
      engine!.tick();
      ready(engine!, clock);
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
        testWidgets('current hold UI $task $locale $scale', (tester) async {
          final c = CurrentController();
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
          expect(find.byType(KeyDurationGuide), findsOneWidget);
          final guide = tester.getRect(find.byType(KeyDurationGuide)),
              keys = tester.getRect(find.byType(PianoKeyboard));
          expect(guide.bottom, lessThanOrEqualTo(keys.top));
          final e = c.engine!, time = e.clock as ManualClock;
          if (task == 'G1_MEMORY' || task == 'G3_SWITCH') {
            expect(e.durationGuide, isNull);
          }
          final key = task == 'G1_MEMORY'
              ? e.expected.first
              : e.expected.single;
          e.down(1, key);
          time.now += 200000;
          e.tick();
          c.notifyListeners();
          await tester.pump();
          expect(
            tester
                .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
                .progress,
            .5,
          );
          if (task == 'S2_RHYTHM') {
            expect(find.byType(RhythmTimeline).hitTestable(), findsOneWidget);
            expect(
              find.bySemanticsLabel(
                locale == 'en' ? 'Whole phrase progress' : '整组演奏进度',
              ),
              findsOneWidget,
            );
          }
          e.pause('USER');
          c.notifyListeners();
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(PianoKeyboard)), keys);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        });
      }
    }
  }
  for (final width in [320.0, 412.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'onboarding matching language buttons and adaptive keys $width $scale',
        (tester) async {
          final c = AppController(repository: MemoryPreferences());
          mocks(tester, Size(width, 740), 'zh-Hans', scale, c);
          c.repository.profile['onboarding_completed'] = 0;
          await tester.pumpWidget(PianoApp(controller: c));
          await tester.pumpAndSettle();
          final zh = find.byKey(const ValueKey('language-zh-Hans')),
              en = find.byKey(const ValueKey('language-en'));
          expect(
            tester
                .widget<OutlinedButton>(zh)
                .style!
                .backgroundColor
                ?.resolve({}),
            isNotNull,
          );
          expect(
            tester
                .widget<OutlinedButton>(en)
                .style!
                .backgroundColor
                ?.resolve({}),
            isNull,
          );
          await tester.ensureVisible(en);
          await tester.pumpAndSettle();
          await tester.tap(en);
          await tester.pumpAndSettle();
          expect(c.locale, 'en');
          expect(
            tester
                .widget<OutlinedButton>(en)
                .style!
                .backgroundColor
                ?.resolve({}),
            isNotNull,
          );
          final next = find.widgetWithText(FilledButton, 'Next');
          await tester.scrollUntilVisible(next, 120);
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pumpAndSettle();
          final keyboard = find.byType(PianoKeyboard);
          await tester.scrollUntilVisible(keyboard, 120);
          await tester.ensureVisible(keyboard);
          await tester.pumpAndSettle();
          expect(
            tester.widget<PianoKeyboard>(keyboard).count,
            width < 400 ? 3 : 5,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
  testWidgets(
    'settings has selected language and two volume cards, no sound switches',
    (tester) async {
      final c = AppController(repository: MemoryPreferences());
      mocks(tester, const Size(412, 740), 'en', 1, c);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Key sounds'), findsNothing);
      expect(find.text('Local spoken guidance'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('language-en')))
            .style!
            .backgroundColor
            ?.resolve({}),
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
