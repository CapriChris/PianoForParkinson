import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/response_countdown.dart';
import 'package:piano_practice/features/training_page.dart';

import 'cognitive_flow_test.dart' show awaitResponse;

Future<void> openTraining(
  WidgetTester tester,
  AppController c,
  ManualClock clock,
  String task,
) async {
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(
        MaterialPageRoute<void>(
          builder: (_) => TrainingPage(c: c, taskId: task),
        ),
      );
  await tester.pumpAndSettle();
  await awaitResponse(tester, c, clock);
  while (task == 'G2_INHIBITION' && c.engine!.target['trial_type'] == 'NO_GO') {
    clock.now += c.engine!.responseWindowUs;
    await tester.pump(const Duration(milliseconds: 20));
    await awaitResponse(tester, c, clock);
  }
  // Cue acknowledgement is post-frame; render the newly active response UI.
  await tester.pump();
}

Future<TestGesture> touchKey(WidgetTester tester, AppController c, int key) {
  final rect = c.layout!['keys'][key]['hit_rect'] as List;
  return tester.startGesture(
    Offset((rect[0] + rect[2] / 2) / 1000, (rect[1] + rect[3] / 2) / 1000),
  );
}

Future<void> backHome(WidgetTester tester, AppController c) async {
  await tester.tap(find.byTooltip('Back'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
  for (
    var i = 0;
    i < 500 && (!c.saved || find.byType(TrainingPage).evaluate().isNotEmpty);
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(c.storageError, isNull);
  expect(c.saved, true);
  expect(find.byType(HomePage), findsOneWidget);
  expect(find.byType(TrainingPage), findsNothing);
  await tester.pumpAndSettle();
}

Future<AppController> setup(WidgetTester tester, ManualClock clock) async {
  final c = AppController(
    clock: clock,
    databaseSubdirectory: 'responsive-${uuid()}',
  );
  await c.initialize();
  expect(c.error, isNull);
  expect(c.audioReady, true);
  final directory = File(c.repository.db.path).parent;
  addTearDown(() async {
    c.dispose();
    if (c.repository.db.isOpen) await c.repository.db.close();
    await directory.delete(recursive: true);
  });
  await c.updateSettings(locale: 'en', onboard: true);
  await tester.pumpWidget(PianoApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'all modes: countdown, persistent short feedback, disabled controls, fill advances, save and back',
    (tester) async {
      final time = ManualClock();
      final c = await setup(tester, time);
      for (final task in [
        'G1_MEMORY',
        'G2_INHIBITION',
        'G3_SWITCH',
        'S1_GUIDED',
        'S2_RHYTHM',
      ]) {
        await openTraining(tester, c, time, task);
        final e = c.engine!, id = e.id;
        expect(
          find.byType(ResponseCountdown),
          task.startsWith('G') ? findsOneWidget : findsNothing,
        );
        if (task != 'S2_RHYTHM') {
          final note = e.expected.first;
          final gesture = await touchKey(tester, c, note);
          time.now += 100000;
          await gesture.up();
          time.now += 1300000;
          await tester.pump(const Duration(milliseconds: 20));
          expect(e.durationTooShort, true);
          expect(find.textContaining('Too short'), findsOneWidget);
          if (e.windowed) {
            expect(
              tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
              true,
            );
            final actionCount = e.events
                .where((v) => v['kind'] == 'KEY_DOWN')
                .length;
            await tester.tapAt(tester.getCenter(find.byType(PianoKeyboard)));
            expect(
              e.events.where((v) => v['kind'] == 'KEY_DOWN').length,
              actionCount,
            );
            time.now += e.responseRemainingUs!;
            await tester.pump(const Duration(milliseconds: 20));
            expect(e.durationTooShort, false);
            await awaitResponse(tester, c, time);
            while (task == 'G2_INHIBITION' &&
                e.target['trial_type'] == 'NO_GO') {
              time.now += e.responseWindowUs;
              await tester.pump(const Duration(milliseconds: 20));
              await awaitResponse(tester, c, time);
            }
            final before = e.completed;
            final held = await touchKey(tester, c, e.expected.single);
            time.now += 400000;
            await tester.pump(const Duration(milliseconds: 20));
            expect(e.completed, before + 1);
            expect(e.durationGuide, isNull);
            expect(e.highlighted, isNull);
            await held.up();
          } else {
            final retry = await touchKey(tester, c, note);
            expect(e.durationTooShort, false);
            time.now += 400000;
            await retry.up();
          }
        }
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        await tester.pumpAndSettle();
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
        expect(
          tester
              .widget<KeyDurationGuide>(find.byType(KeyDurationGuide))
              .targetKey,
          isNull,
        );
        await c.flush();
        expect(c.storageError, isNull);
        await backHome(tester, c);
        expect(
          (await c.repository.db.query(
            'sessions',
            where: 'session_id=?',
            whereArgs: [id],
          )).single['status'],
          'EXITED',
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'G1 replay demo does not hint; more help replays then hints and persists',
    (tester) async {
      final clock = ManualClock();
      final c = await setup(tester, clock);
      await openTraining(tester, c, clock, 'G1_MEMORY');
      final e = c.engine!;
      final target = canonical(e.target);
      for (final help in [false, true]) {
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey(help ? 'more-help' : 'replay-demo')),
        );
        for (var i = 0; i < 300 && e.phase == 'paused'; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await awaitResponse(tester, c, clock);
        expect(canonical(e.target), target);
        expect(e.showAnswer, help);
        expect(e.highlighted, help ? e.expected.first : isNull);
        await c.flush();
        expect(c.storageError, isNull);
      }
      await backHome(tester, c);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
