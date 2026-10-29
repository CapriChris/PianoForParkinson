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
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/features/trend_page.dart';

import 'cognitive_flow_test.dart' show awaitResponse, visibleTap;
import 'live_clock_flow_test.dart' as live;
import 'android_contract_test.dart' show advance;
import 'responsive_flow_test.dart' show backHome;
import '../test/domain/alternate_test.dart' show answer;

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

Future<void> liveResponse(WidgetTester tester, AppController c) async {
  for (var i = 0; i < 2500; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (c.engine?.phase == 'response') return;
    expect(
      c.engine?.phase,
      isNot('paused'),
      reason: '${c.storageError} / ${c.engine?.pauseReason}',
    );
  }
  fail('M1 response not reached');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'M1 committed block survives recovery; unfinished window is excluded',
    (tester) async {
      final c = AppController(
        databaseSubdirectory: 'alternate-recovery-${uuid()}',
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
            taskId: 'M1_ALTERNATE',
            mode: 'ASSIST',
            level: 2,
            song: [4, 4, 4],
            seed: 47,
            layoutSnapshot: {'layout_id': 'ALTERNATE_TWO_KEYS'},
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
        null,
        'Asia/Shanghai',
      );
      for (var i = 0; i < e.song.length; i++) {
        answer(e, time);
      }
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
      expect(summary['completed'], 12);
      expect(summary['sample_counts']['interrupted'], 1);
      expect(summary['active_duration_us'], 9600000);
      expect(await current.trendConditions(taskId: e.taskId), sealed);
      expect(clock.now, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'M1 menu, fixed two-block phrase, pause, SQLite metrics and trend',
    (tester) async {
      final clock = ManualClock(),
          c = AppController(
            clock: ManualClock(),
            databaseSubdirectory: 'alternate-flow-${uuid()}',
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
      final card = find.widgetWithText(PracticeCard, 'Alternating keys');
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
        for (var note = 0; note < 12; note++) {
          debugPrint('M1 block $block note $note: waiting');
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
          debugPrint('M1 block $block note $note: saved');
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
      expect(result['rates']['primary'], {'numerator': 24, 'denominator': 24});
      expect(result['timing_groups']['beat_error_absolute']['samples'], 24);
      expect(result['timing_groups']['alternate_hit_interval']['samples'], 21);
      await visibleTap(
        tester,
        find.text('Practice details'),
        find.byType(ResultPage),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('CV '), findsOneWidget);
      await tester.tap(find.text('Practice details'));
      await tester.pumpAndSettle();
      expect(record['content_id'], isNull);
      expect(
        await c.repository.db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      final stored = await c.repository.db.query(
        'attempts',
        where: "session_id=? AND validity='VALID'",
        whereArgs: [c.engine!.id],
      );
      expect(stored, hasLength(24));
      expect(c.engine!.blocks.every((b) => b['status'] == 'COMPLETED'), true);
      expect(
        await c.repository.trendConditions(taskId: 'M1_ALTERNATE'),
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
    'M1 real clock, reference audio, hold bar, pause continues and back saves',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'alternate-live-${uuid()}');
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
              builder: (_) => TrainingPage(c: c, taskId: 'M1_ALTERNATE'),
            ),
          );
      await tester.pump();
      await liveResponse(tester, c);
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
      await backHome(tester, c);
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
}
