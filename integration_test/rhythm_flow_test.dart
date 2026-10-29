import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/audio_volume_control.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/trend_page.dart';

import 'cognitive_flow_test.dart' show awaitResponse, visibleTap;
import 'live_clock_flow_test.dart' as live;
import 'android_contract_test.dart' show advance;

void cleanup(AppController c) {
  final directory = File(c.repository.db.path).parent;
  addTearDown(() async {
    c.dispose();
    if (c.repository.db.isOpen) await c.repository.db.close();
    await directory.delete(recursive: true);
  });
}

Future<void> saved(WidgetTester tester, AppController c) async {
  for (var i = 0; i < 300 && !c.saved; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(c.storageError, isNull);
  expect(c.saved, true);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'S2 committed block survives recovery; unfinished window is excluded',
    (tester) async {
      final c = AppController(
        databaseSubdirectory: 'rhythm-recovery-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
      final directory = File(c.repository.db.path).parent;
      PracticeRepository current = c.repository;
      addTearDown(() async {
        c.dispose();
        if (current.db.isOpen) await current.db.close();
        await directory.delete(recursive: true);
      });
      final clock = ManualClock(),
          e = TaskEngine(
            config: c.content.config,
            clock: ManualClock(),
            taskId: 'S2_RHYTHM',
            mode: 'ASSIST',
            level: 2,
            song: c.content.notes,
            seed: 47,
            layoutSnapshot: {'layout_id': 'WIDE'},
          );
      final time = e.clock as ManualClock;
      await current.create(
        e,
        {
          'schema_version': 1,
          'device_local_id': 'test',
          'clock_source': 'DART_RECEIPT',
          'sound_enabled': false,
          'app_gain_permille': 850,
          'audio_route_category': 'MUTED',
          'layout_version': 1,
        },
        c.content.song,
        'Asia/Shanghai',
      );
      for (var i = 0; i < e.song.length; i++) {
        advance(e, time);
        time.now = e.scheduledBeatUs;
        e.down(1, e.expected.single);
        e.up(1);
        time.now = e.scheduledBeatUs + e.beatAfterUs;
        e.tick();
      }
      time.now = e.base + e.phraseEndUs;
      e.tick();
      await current.persist(e);
      final sealed = await current.trendConditions(taskId: e.taskId);
      e.nextBlock();
      advance(e, time);
      await current.persist(e);
      await current.db.close();
      current = PracticeRepository();
      await current.open(directory.path, 'en');
      final record = (await current.detail(e.id))!,
          summary = jsonDecode(record['result_json'] as String);
      expect(record['status'], 'RECOVERED_INTERRUPTED');
      expect(summary['completed'], 8);
      expect(summary['sample_counts']['interrupted'], 1);
      expect(summary['active_duration_us'], 6400000);
      expect(await current.trendConditions(taskId: e.taskId), sealed);
      expect(clock.now, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'S2 menu, fixed two-block phrase, pause, SQLite metrics and trend',
    (tester) async {
      final clock = ManualClock(),
          c = AppController(
            clock: ManualClock(),
            databaseSubdirectory: 'rhythm-flow-${uuid()}',
          );
      final time = c.clock as ManualClock;
      await c.initialize();
      expect(c.error, isNull);
      cleanup(c);
      await c.updateSettings(
        locale: 'en',
        onboard: true,
        values: {...c.settings, 'sound_enabled': false},
      );
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      final card = find.widgetWithText(PracticeCard, 'Rhythm practice');
      await visibleTap(
        tester,
        find.descendant(of: card, matching: find.byType(FilledButton)),
        find.byType(HomePage),
      );
      await tester.pumpAndSettle();
      await visibleTap(
        tester,
        find.widgetWithText(FilledButton, 'Start practice'),
        find.byType(InstructionPage),
      );
      await tester.pumpAndSettle();
      for (var block = 0; block < 2; block++) {
        for (var note = 0; note < c.content.notes.length; note++) {
          await awaitResponse(tester, c, time);
          final e = c.engine!;
          if (block == 0 && note == 0) {
            final attempt = e.attempts.last['attempt_id'];
            final demos = e.events
                .where(
                  (v) =>
                      v['kind'] == 'AUDIO_REQUEST' &&
                      v['payload']['owner'] == 'DEMO',
                )
                .length;
            await tester.tap(find.byKey(const ValueKey('pause-toggle')));
            await tester.pumpAndSettle();
            time.now += 3000000;
            await tester.tap(find.byKey(const ValueKey('pause-toggle')));
            for (var i = 0; i < 200 && (c.busy || e.phase == 'paused'); i++) {
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(e.attempts.last['attempt_id'], attempt);
            expect(
              e.events
                  .where(
                    (v) =>
                        v['kind'] == 'AUDIO_REQUEST' &&
                        v['payload']['owner'] == 'DEMO',
                  )
                  .length,
              demos,
            );
          }
          time.now = e.base + e.scheduledBeatUs;
          final targetEnd = time.now + e.beatAfterUs;
          await live.tapNote(tester, c, e.expected.single);
          if (time.now < targetEnd) time.now = targetEnd;
          await tester.pump(const Duration(milliseconds: 30));
          await c.flush();
          expect(c.storageError, isNull);
          final valid = e.attempts.lastWhere((a) => a['validity'] == 'VALID');
          expect(valid['result']['outcome'], 'HIT');
          expect(valid['result']['beat_error_us'], 0);
          expect(valid['active_duration_us'], 800000);
        }
        expect(c.engine!.finishingPhrase, true);
        expect(c.engine!.ended, false);
        expect(c.engine!.phraseProgress, lessThan(1));
        time.now = c.engine!.base + c.engine!.phraseEndUs;
        await tester.pump(const Duration(milliseconds: 30));
        if (block == 0) {
          await tester.tap(find.text('Next block'));
          await tester.pump(const Duration(milliseconds: 40));
        }
      }
      await saved(tester, c);
      expect(find.byType(ResultPage), findsOneWidget);
      final record = (await c.repository.detail(c.engine!.id))!;
      final result = jsonDecode(record['result_json'] as String);
      expect(result['rates']['primary'], {'numerator': 16, 'denominator': 16});
      expect(result['timing_groups']['beat_error_absolute']['samples'], 16);
      final stored = await c.repository.db.query(
        'attempts',
        where: "session_id=? AND validity='VALID'",
        whereArgs: [c.engine!.id],
      );
      expect(stored, hasLength(16));
      expect(c.engine!.blocks.every((b) => b['status'] == 'COMPLETED'), true);
      expect(
        await c.repository.trendConditions(taskId: 'S2_RHYTHM'),
        isNotEmpty,
      );
      await visibleTap(
        tester,
        find.text('Compare practice blocks'),
        find.byType(ResultPage),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TrendChart), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(clock.now, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'S2 real clock, reference audio, hold bar, pause continues and back saves',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'rhythm-live-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      expect(c.audioReady, true);
      cleanup(c);
      await c.updateSettings(locale: 'en', onboard: true);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => TrainingPage(c: c, taskId: 'S2_RHYTHM'),
            ),
          );
      await tester.pump(const Duration(milliseconds: 500));
      await live.awaitResponse(tester, c);
      final e = c.engine!, attempt = c.engine!.attempts.last['attempt_id'];
      final demos = e.events
          .where(
            (v) =>
                v['kind'] == 'AUDIO_REQUEST' && v['payload']['owner'] == 'DEMO',
          )
          .length;
      await tester.tap(find.byKey(const ValueKey('pause-toggle')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('pause-toggle')));
      for (var i = 0; i < 200 && (c.busy || e.phase == 'paused'); i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(e.attempts.last['attempt_id'], attempt);
      expect(
        e.events
            .where(
              (v) =>
                  v['kind'] == 'AUDIO_REQUEST' &&
                  v['payload']['owner'] == 'DEMO',
            )
            .length,
        demos,
      );
      while (e.now < e.scheduledBeatUs) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final rect = c.layout!['keys'][e.expected.single]['hit_rect'] as List;
      final gesture = await tester.startGesture(
        Offset((rect[0] + rect[2] / 2) / 1000, (rect[1] + rect[3] / 2) / 1000),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<KeyDurationGuide>(find.byType(KeyDurationGuide)).progress,
        greaterThan(.3),
      );
      await tester.pump(const Duration(milliseconds: 210));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 30));
      expect(e.completed, greaterThanOrEqualTo(1));
      await c.flush();
      expect(c.storageError, isNull);
      final valid = e.attempts.firstWhere((a) => a['validity'] == 'VALID');
      expect(valid['outcome'], 'HIT');
      expect(valid['active_duration_us'], 800000);
      expect(e.events.where((v) => v['kind'] == 'BEAT_REFERENCE'), isNotEmpty);
      final caps = await c.platform.call('getCapabilities');
      expect(caps['status_bar_hidden'], true);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
      expect(c.saved, true);
      var homeDisplay = await c.platform.call('getCapabilities');
      for (var i = 0; i < 50 && homeDisplay['status_bar_hidden'] == true; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        homeDisplay = await c.platform.call('getCapabilities');
      }
      expect(homeDisplay['training_fullscreen'], false);
      expect(homeDisplay['status_bar_hidden'], false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'independent key and speech gain: UI, native volume, legacy JSON and restart',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'audio-settings-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      cleanup(c);
      await c.updateSettings(locale: 'en', onboard: true);
      expect(c.settings['gain_permille'], 850);
      expect(c.settings['speech_gain_permille'], 1000);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      for (final entry in {
        'gain_permille': 1000,
        'speech_gain_permille': 350,
      }.entries) {
        final slider = find.byKey(ValueKey(entry.key));
        await tester.scrollUntilVisible(
          slider,
          200,
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
        await tester.pumpAndSettle();
      }
      expect(c.settings['gain_permille'], 1000);
      expect(c.settings['speech_gain_permille'], 350);
      final sound = await c.platform.call('playNote', {
        'note_id': 0,
        'voice_request_id': uuid(),
        'gain_permille': c.settings['gain_permille'],
        'owner': 'SANDBOX',
      });
      expect(sound['applied_gain_permille'], 1000);
      await c.platform.stop(sound['voice_id']);
      if ((c.capabilities['tts_locales'] as List).any(
        (v) => '$v'.startsWith('en'),
      )) {
        final speech = await c.platform.call('speakLocal', {
          'locale': 'en',
          'resolved_text': 'Volume test.',
          'gain_permille': c.settings['speech_gain_permille'],
        });
        expect(speech['accepted'], true);
        expect(speech['applied_gain_permille'], 350);
        await c.platform.call('stopSpeech');
      }
      await Future.wait([
        c.updateAudioGain('gain_permille', 250),
        c.updateAudioGain('speech_gain_permille', 700),
      ]);
      await c.repository.reload();
      expect(c.settings['gain_permille'], 250);
      expect(c.settings['speech_gain_permille'], 700);
      expect(find.byType(AudioVolumeControl), findsWidgets);
      await expectLater(
        c.repository.settingsUpdate(
          settings: {...c.settings, 'speech_gain_permille': 1001},
        ),
        throwsFormatException,
      );
      final old = {...c.settings, 'gain_permille': 600}
        ..remove('speech_gain_permille');
      await c.repository.db.update(
        'profiles',
        {'settings_json': canonical(old)},
        where: 'profile_id=?',
        whereArgs: [c.repository.profile['profile_id']],
      );
      await tester.pumpWidget(const SizedBox());
      final directory = File(c.repository.db.path).parent;
      await c.repository.db.close();
      final reopened = PracticeRepository();
      await reopened.open(directory.path, 'en');
      expect(reopened.settings['gain_permille'], 850);
      expect(reopened.settings['speech_gain_permille'], 1000);
      await reopened.settingsUpdate(
        settings: {
          ...reopened.settings,
          'gain_permille': 600,
          'speech_gain_permille': 0,
          'sound_enabled': false,
        },
      );
      await reopened.db.close();
      final again = PracticeRepository();
      await again.open(directory.path, 'en');
      expect(again.settings['gain_permille'], 600);
      expect(again.settings['speech_gain_permille'], 0);
      expect(again.settings['sound_enabled'], false);
      await again.db.close();
    },
  );
}
