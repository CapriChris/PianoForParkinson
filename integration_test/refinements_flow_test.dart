import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/key_duration_guide.dart';

import 'cognitive_flow_test.dart' show awaitResponse, visibleTap;
import 'live_clock_flow_test.dart' show tapNote;

void clean(AppController c) {
  final directory = File(c.repository.db.path).parent;
  addTearDown(() async {
    c.dispose();
    if (c.repository.db.isOpen) await c.repository.db.close();
    await directory.delete(recursive: true);
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'onboarding language styles, responsive keys, sampled piano and independent volume-only settings',
    (tester) async {
      final c = AppController(
        databaseSubdirectory: 'refine-settings-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
      expect(c.audioReady, true);
      clean(c);
      await c.updateSettings(locale: 'en');
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('language-en')), findsOneWidget);
      expect(find.byKey(const ValueKey('language-zh-Hans')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language-zh-Hans')));
      for (var i = 0; i < 200 && c.locale != 'zh-Hans'; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(c.locale, 'zh-Hans');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-en')));
      for (var i = 0; i < 200 && c.locale != 'en'; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Next'),
        find.byType(Onboarding),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).count, 5);
      expect(c.content.soundPack['assets'][0]['author'], 'Alexander Holm');
      expect(c.content.soundPack['assets'][0]['license_id'], 'CC-BY-3.0');
      await c.preview(0, true);
      await tester.pump(const Duration(milliseconds: 450));
      await c.preview(0, false);
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Next'),
        find.byType(Onboarding),
      );
      await tester.pumpAndSettle();
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Get started'),
        find.byType(Onboarding),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Key sounds'), findsNothing);
      expect(find.text('Local spoken guidance'), findsNothing);
      for (final entry in {
        'gain_permille': 650,
        'speech_gain_permille': 450,
      }.entries) {
        final slider = find.byKey(ValueKey(entry.key));
        await tester.scrollUntilVisible(
          slider,
          180,
          scrollable: find
              .descendant(
                of: find.byType(SettingsPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        tester.widget<Slider>(slider).onChanged!(entry.value.toDouble());
        tester.widget<Slider>(slider).onChangeEnd!(entry.value.toDouble());
        for (var i = 0; i < 200 && c.settings[entry.key] != entry.value; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
      await c.repository.reload();
      expect(c.settings['gain_permille'], 650);
      expect(c.settings['speech_gain_permille'], 450);
      await c.updateAudioGain('gain_permille', 0);
      expect(c.soundEnabled, false);
      await c.updateAudioGain('gain_permille', 650);
      expect(c.soundEnabled, true);
      await c.updateSettings(values: {...c.settings, 'speech_enabled': false});
      await c.updateAudioGain('speech_gain_permille', 450);
      expect(c.settings['speech_enabled'], true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'all five current modes: short-press policy, hold bars, replay or skip, SQLite and back',
    (tester) async {
      final time = ManualClock(),
          c = AppController(
            clock: ManualClock(),
            databaseSubdirectory: 'refine-training-${uuid()}',
          );
      final clock = c.clock as ManualClock;
      await c.initialize();
      expect(c.error, isNull);
      clean(c);
      await c.updateSettings(
        locale: 'en',
        onboard: true,
        values: {...c.settings, 'sound_enabled': false},
      );
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      for (final task in [
        'G1_MEMORY',
        'S1_GUIDED',
        'G2_INHIBITION',
        'G3_SWITCH',
        'S2_RHYTHM',
      ]) {
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => TrainingPage(c: c, taskId: task),
              ),
            );
        await tester.pump(const Duration(milliseconds: 500));
        await awaitResponse(tester, c, clock);
        final e = c.engine!;
        while (task == 'G2_INHIBITION' && e.target['trial_type'] == 'NO_GO') {
          clock.now += e.responseWindowUs;
          await tester.pump(const Duration(milliseconds: 20));
          await awaitResponse(tester, c, clock);
        }
        final before = e.completed, trial = e.trial['trial_id'];
        if (e.rhythm) clock.now = e.base + e.scheduledBeatUs;
        final key = e.memory ? e.expected.first : e.expected.single;
        final r = c.layout!['keys'][key]['hit_rect'] as List;
        final gesture = await tester.startGesture(
          Offset((r[0] + r[2] / 2) / 1000, (r[1] + r[3] / 2) / 1000),
        );
        clock.now += 100000;
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          tester
              .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
              .progress,
          closeTo(.25, .01),
        );
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 20));
        if (e.memory || task == 'S1_GUIDED') {
          expect(e.completed, before);
          expect(e.trial['trial_id'], trial);
          final keys = List<int>.from(e.expected);
          for (final k in keys) {
            await tapNote(tester, c, k);
          }
          if (e.memory) {
            clock.now += 300000;
            await tester.pump(const Duration(milliseconds: 20));
          }
        } else {
          clock.now += e.rhythm ? 400000 : e.responseWindowUs;
          await tester.pump(const Duration(milliseconds: 20));
          final short = e.attempts.lastWhere((a) => a['validity'] == 'VALID');
          expect(short['outcome'], 'TOO_SHORT');
          expect(e.completed, before + 1);
        }
        await c.flush();
        expect(c.storageError, isNull);
        expect(
          (await c.repository.db.query(
            'attempts',
            where: "session_id=? AND validity='VALID'",
            whereArgs: [e.id],
          )),
          isNotEmpty,
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), findsOneWidget);
        expect(c.saved, true);
        expect(tester.takeException(), isNull);
      }
      expect(time.now, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
