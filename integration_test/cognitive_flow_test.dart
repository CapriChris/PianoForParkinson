import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/cognitive_tasks.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/switch_tutorial_page.dart';
import 'package:piano_practice/features/trend_page.dart';

import 'android_contract_test.dart' show advance;
import 'app_flow_test.dart' show key;

Future<void> awaitResponse(
  WidgetTester tester,
  AppController c,
  ManualClock clock,
) async {
  for (var i = 0; i < 400; i++) {
    if (c.engine?.phase == 'response' && c.engine?.ended == false) return;
    expect(c.storageError, isNull);
    expect(c.engine?.phase, isNot('paused'));
    if (c.engine?.phase != 'cue') clock.now += 200000;
    await tester.pump(const Duration(milliseconds: 20));
  }
  throw StateError('No response: ${c.engine?.phase}');
}

Future<void> visibleTap(WidgetTester tester, Finder target, Finder page) async {
  await tester.scrollUntilVisible(
    target,
    150,
    scrollable: find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first,
  );
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(target);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'G2 and G3: menu, unscored examples, two blocks, pause, results and trends',
    (tester) async {
      final clock = ManualClock();
      final c = AppController(
        clock: clock,
        databaseSubdirectory: 'cognitive-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
      final directory = File(c.repository.db.path).parent;
      addTearDown(() async {
        c.dispose();
        if (c.repository.db.isOpen) await c.repository.db.close();
        await directory.delete(recursive: true);
      });
      await c.updateSettings(
        locale: 'en',
        onboard: true,
        values: {...c.settings, 'sound_enabled': false},
      );
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
        final card = find.widgetWithText(PracticeCard, taskTitle(task, false));
        final practice = find.descendant(
          of: card,
          matching: find.byType(FilledButton),
        );
        await visibleTap(tester, practice, find.byType(HomePage));
        await tester.pumpAndSettle();
        await visibleTap(
          tester,
          find.widgetWithText(FilledButton, 'Start practice'),
          find.byType(InstructionPage),
        );
        await tester.pumpAndSettle();
        if (task == 'G3_SWITCH') {
          expect(find.byType(SwitchTutorialPage), findsOneWidget);
          final before = (await c.repository.db.query('sessions')).length;
          for (final target in [0, 2, 1, 2]) {
            await tester.ensureVisible(find.byType(PianoKeyboard));
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.byType(PianoKeyboard));
            final width = (rect.width - 16) / 3;
            await tester.tapAt(
              Offset(
                rect.left + target * (width + 8) + width / 2,
                rect.center.dy,
              ),
            );
            await tester.pumpAndSettle();
            await visibleTap(
              tester,
              find.text('Next example'),
              find.byType(SwitchTutorialPage),
            );
            await tester.pumpAndSettle();
          }
          expect((await c.repository.db.query('sessions')).length, before);
          await visibleTap(
            tester,
            find.widgetWithText(FilledButton, 'Start practice'),
            find.byType(SwitchTutorialPage),
          );
        }
        await tester.pump(const Duration(milliseconds: 500));
        for (var block = 0; block < 2; block++) {
          for (var trial = 0; trial < 12; trial++) {
            await awaitResponse(tester, c, clock);
            if (block == 0 && trial == 0) {
              final attempt = c.engine!.attempts.last['attempt_id'],
                  target = canonical(c.engine!.target);
              await tester.tap(find.byKey(const ValueKey('pause-toggle')));
              await tester.pumpAndSettle();
              clock.now += 9000000;
              await tester.pump(const Duration(milliseconds: 20));
              expect(c.engine!.phase, 'paused');
              await tester.tap(find.byKey(const ValueKey('pause-toggle')));
              for (var i = 0; i < 100 && c.engine!.phase == 'paused'; i++) {
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(c.engine!.attempts.last['attempt_id'], attempt);
              expect(canonical(c.engine!.target), target);
            }
            final completed = c.engine!.completed;
            if (c.engine!.target['trial_type'] == 'GO') {
              await key(tester, c, clock, c.engine!.expected.single);
            }
            if (c.engine!.completed == completed) {
              clock.now += c.engine!.responseWindowUs;
            }
            for (var i = 0; i < 100 && c.engine!.completed == completed; i++) {
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(c.engine!.completed, completed + 1);
          }
          if (block == 0) {
            await tester.tap(find.text('Next block'));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        for (var i = 0; i < 150 && !c.saved; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(c.storageError, isNull);
        expect(c.saved, true);
        await tester.pumpAndSettle();
        final record = (await c.repository.detail(c.engine!.id))!,
            summary = jsonDecode(record['result_json'] as String) as Json;
        expect(record['content_id'], isNull);
        if (task == 'G3_SWITCH') {
          final trials = await c.repository.db.query(
            'trials',
            where: 'session_id=?',
            whereArgs: [c.engine!.id],
            orderBy: 'logical_index',
          );
          expect(
            trials.where((t) => t['rule_id'] == 'POSITION'),
            hasLength(12),
          );
          expect(trials.where((t) => t['rule_id'] == 'SHAPE'), hasLength(12));
          expect(trials.where((t) => t['switch_flag'] == null), hasLength(2));
          expect(trials.where((t) => t['switch_flag'] == 1), hasLength(2));
        }
        expect(summary['completed'], 24);
        expect(summary['rates']['primary'], {
          'numerator': task == 'G2_INHIBITION' ? 18 : 24,
          'denominator': task == 'G2_INHIBITION' ? 18 : 24,
        });
        if (task == 'G2_INHIBITION') {
          expect(summary['rates']['no_go_commission'], {
            'numerator': 0,
            'denominator': 6,
          });
        }
        await visibleTap(
          tester,
          find.text('Practice details'),
          find.byType(ResultPage),
        );
        await tester.pumpAndSettle();
        expect(find.text(primaryMetricTitle(task, false)), findsOneWidget);
        final conditions = await c.repository.trendConditions(taskId: task);
        expect(conditions, hasLength(2));
        await visibleTap(
          tester,
          find.text('Compare practice blocks'),
          find.byType(ResultPage),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TrendPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.pop(tester.element(find.byType(TrendPage)));
        await tester.pumpAndSettle();
        await visibleTap(
          tester,
          find.widgetWithText(OutlinedButton, 'Home'),
          find.byType(ResultPage),
        );
        await tester.pumpAndSettle();
      }
      expect(c.history, hasLength(2));
      expect(
        await c.repository.db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    testWidgets(
      '$task committed block survives process recovery with unfinished window excluded',
      (tester) async {
        final c = AppController(
          databaseSubdirectory: 'recover-cognitive-${uuid()}',
        );
        await c.initialize();
        final directory = File(c.repository.db.path).parent;
        final clock = ManualClock();
        final e = TaskEngine(
          config: c.content.config,
          clock: clock,
          taskId: task,
          mode: 'ASSIST',
          level: 2,
          song: [],
          seed: 47,
          layoutSnapshot: {'layout_id': 'WIDE'},
        );
        await c.repository.create(
          e,
          {
            'schema_version': 1,
            'device_local_id': 'test',
            'clock_source': 'DART_RECEIPT',
            'sound_enabled': false,
            'app_gain_permille': 600,
            'audio_route_category': 'MUTED',
            'layout_version': 1,
          },
          null,
          'Asia/Shanghai',
        );
        for (var i = 0; i < 12; i++) {
          advance(e, clock);
          if (e.target['trial_type'] == 'GO') {
            e.down(1, e.expected.single);
            e.up(1);
          }
          clock.now += e.responseWindowUs;
          e.tick();
        }
        await c.repository.persist(e);
        final sealed = await c.repository.trendConditions(taskId: task);
        e.nextBlock();
        advance(e, clock);
        await c.repository.persist(e);
        await c.repository.db.close();
        final reopened = PracticeRepository();
        await reopened.open(directory.path, 'en');
        final record = (await reopened.detail(e.id))!,
            summary = jsonDecode(record['result_json'] as String) as Json;
        expect(record['status'], 'RECOVERED_INTERRUPTED');
        expect(summary['completed'], 12);
        expect(summary['sample_counts']['interrupted'], 1);
        expect(await reopened.trendConditions(taskId: task), sealed);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await reopened.db.close();
        await directory.delete(recursive: true);
      },
    );
  }
}
