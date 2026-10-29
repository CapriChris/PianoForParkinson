import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/audio_volume_control.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/data/practice_repository.dart';

import '../domain/task_engine_test.dart' show create, ready;
import 'cognitive_pages_test.dart' show mocks;

class RhythmController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    engine = create(clock, task: taskId);
    layout = keyboardLayout;
    engine!.layoutSnapshot = keyboardLayout;
    ready(engine!, clock);
    notifyListeners();
  }
}

class MemoryPreferences extends PracticeRepository {
  @override
  Future<void> settingsUpdate({
    String? locale,
    String? mode,
    Json? settings,
    bool onboard = false,
  }) async {
    profile = {
      ...profile,
      'locale': ?locale,
      'mode': ?mode,
      if (settings != null) 'settings_json': canonical(settings),
    };
  }
}

void main() {
  for (final size in [const Size(640, 360), const Size(800, 360)]) {
    for (final language in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'rhythm cue, hold bar, inline pause and results $size $language $scale',
          (tester) async {
            final c = RhythmController();
            mocks(tester, size, language, scale, c);
            await tester.pumpWidget(PianoApp(controller: c));
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainingPage(c: c, taskId: 'S2_RHYTHM'),
                  ),
                );
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 1));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final keyboard = tester.getRect(find.byType(PianoKeyboard));
            final guide = tester.getRect(find.byType(KeyDurationGuide));
            expect(guide.bottom, lessThanOrEqualTo(keyboard.top));
            expect(guide.width, keyboard.width);
            expect(guide.height, 24);
            final e = c.engine!, clock = e.clock as ManualClock;
            e.down(1, e.expected.single);
            clock.now += 200000;
            e.tick();
            c.notifyListeners();
            await tester.pump();
            expect(
              tester
                  .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
                  .progress,
              .5,
            );
            e.pause('USER');
            c.notifyListeners();
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('pause-menu')), findsOneWidget);
            expect(find.text('继续练习'), findsNothing);
            expect(find.text('返回首页'), findsNothing);
            expect(tester.getRect(find.byType(PianoKeyboard)), keyboard);
            expect(
              tester
                  .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
                  .paused,
              true,
            );
            e.finish('EXITED');
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResultPage(
                      c: c,
                      record: {
                        'task_id': e.taskId,
                        'status': 'EXITED',
                        'parameter_profile_version': 'demo',
                        'metric_version': 'metrics-1.0.0',
                        'mode': 'ASSIST',
                        'result_json': canonical(e.summary()),
                      },
                    ),
                  ),
                );
            await tester.pumpAndSettle();
            final title = find.text(
              language == 'en' ? 'Practice details' : '详细训练表现',
            );
            await tester.scrollUntilVisible(
              title,
              120,
              scrollable: find
                  .descendant(
                    of: find.byType(ResultPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.ensureVisible(title);
            await tester.pumpAndSettle();
            await tester.tap(title);
            await tester.pumpAndSettle();
            final metric = find.byWidgetPredicate(
              (w) =>
                  w is MetricTiming &&
                  w.label ==
                      (language == 'en' ? 'Absolute beat error' : '绝对节拍误差'),
            );
            await tester.ensureVisible(metric);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
  for (final language in ['zh-Hans', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'independent audio cards, sliders and persistence $language $scale',
        (tester) async {
          final c = AppController(repository: MemoryPreferences());
          mocks(tester, const Size(360, 640), language, scale, c);
          c.capabilities = {
            'tts_locales': ['en-US', 'zh-CN'],
          };
          c.repository.profile['settings_json'] = jsonEncode({
            ...c.settings,
            'sound_enabled': true,
            'speech_enabled': true,
          });
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language == 'en' ? 'en' : 'zh'),
              home: SettingsPage(c: c),
            ),
          );
          await tester.pumpAndSettle();
          final keySlider = find.byKey(const ValueKey('gain_permille'));
          await tester.scrollUntilVisible(keySlider, 160);
          await tester.ensureVisible(keySlider);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final keyWidget = tester.widget<Slider>(keySlider);
          keyWidget.onChanged!(250);
          keyWidget.onChangeEnd!(250);
          await tester.pumpAndSettle();
          expect(c.settings['gain_permille'], 250);
          expect(c.settings['speech_gain_permille'], 1000);
          final speechSlider = find.byKey(
            const ValueKey('speech_gain_permille'),
          );
          await tester.scrollUntilVisible(speechSlider, 160);
          await tester.ensureVisible(speechSlider);
          await tester.pumpAndSettle();
          final speechWidget = tester.widget<Slider>(speechSlider);
          speechWidget.onChanged!(450);
          speechWidget.onChangeEnd!(450);
          await tester.pumpAndSettle();
          expect(c.settings['gain_permille'], 250);
          expect(c.settings['speech_gain_permille'], 450);
          expect(find.byType(AudioVolumeControl), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
  testWidgets('queued audio writes never overwrite the other channel', (
    tester,
  ) async {
    final c = AppController(repository: MemoryPreferences());
    mocks(tester, const Size(360, 640), 'en', 1, c);
    await Future.wait([
      c.updateAudioGain('gain_permille', 300),
      c.updateAudioGain('speech_gain_permille', 700),
    ]);
    expect(c.settings['gain_permille'], 300);
    expect(c.settings['speech_gain_permille'], 700);
    expect(() => c.updateAudioGain('gain_permille', 1001), throwsArgumentError);
    c.dispose();
  });
}
