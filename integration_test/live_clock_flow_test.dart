import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/training_page.dart';

Future<void> awaitResponse(WidgetTester tester, AppController c) async {
  for (var i = 0; i < 1200; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (c.engine?.phase == 'response') return;
    expect(
      c.engine?.phase,
      isNot('paused'),
      reason: '${c.storageError} / ${c.engine?.pauseReason}',
    );
  }
  fail('Response phase not reached');
}

Future<void> tapNote(WidgetTester tester, AppController c, int key) async {
  final rect = c.layout!['keys'][key]['hit_rect'] as List;
  final gesture = await tester.startGesture(
    Offset((rect[0] + rect[2] / 2) / 1000, (rect[1] + rect[3] / 2) / 1000),
  );
  if (c.engine?.requiresHold == true) {
    if (c.clock is ManualClock) (c.clock as ManualClock).now += 420000;
    await tester.pump(const Duration(milliseconds: 420));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 30));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real clock and sound: first notes save, pause actions, failed save can return Home',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'live-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      expect(c.audioReady, true);
      await c.updateSettings(locale: 'en', onboard: true);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      for (final task in ['G1_MEMORY', 'S1_GUIDED']) {
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => TrainingPage(c: c, taskId: task),
              ),
            );
        await tester.pump(const Duration(seconds: 1));
        await awaitResponse(tester, c);
        final display = await c.platform.call('getCapabilities');
        expect(display['training_fullscreen'], true);
        expect(display['status_bar_hidden'], true);
        final notes = List<int>.from(c.engine!.expected);
        if (task == 'G1_MEMORY') await tapNote(tester, c, notes.removeAt(0));
        final attemptId = c.engine!.attempts.last['attempt_id'];
        final demos = c.engine!.events
            .where(
              (e) =>
                  e['kind'] == 'AUDIO_REQUEST' &&
                  e['payload']['owner'] == 'DEMO',
            )
            .length;
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        await tester.pumpAndSettle();
        expect(c.engine!.phase, 'paused');
        expect(find.text('Continue'), findsOneWidget);
        expect(find.text('Need help'), findsNothing);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        for (
          var i = 0;
          i < 50 && (c.busy || c.engine!.phase == 'paused');
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(c.engine!.phase, 'response');
        expect(c.engine!.attempts.last['attempt_id'], attemptId);
        expect(
          c.engine!.events
              .where(
                (e) =>
                    e['kind'] == 'AUDIO_REQUEST' &&
                    e['payload']['owner'] == 'DEMO',
              )
              .length,
          demos,
        );
        for (final note in notes) {
          await tapNote(tester, c, note);
        }
        if (task == 'G1_MEMORY') {
          await tester.pump(const Duration(milliseconds: 400));
        }
        await c.flush();
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.engine!.completed, 1);
        expect(c.storageError, isNull);
        expect(c.engine!.phase, isNot('paused'));
        expect(
          await c.repository.db.query(
            'attempts',
            where: "session_id=? AND validity='VALID'",
            whereArgs: [c.engine!.id],
          ),
          hasLength(1),
        );
        c.pause('USER');
        await c.flush();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pause-menu')), findsOneWidget);
        if (task == 'G1_MEMORY') {
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
          await tester.pumpAndSettle();
          expect(find.byType(HomePage), findsOneWidget);
          expect(c.saved, true);
        } else {
          await c.repository.db.execute(
            "CREATE TRIGGER fail_session_write BEFORE UPDATE ON sessions BEGIN SELECT RAISE(ABORT, 'injected write failure'); END",
          );
          await c.flush();
          await tester.pumpAndSettle();
          expect(c.storageError, isNotNull);
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
          await tester.pumpAndSettle();
          expect(find.text('Leave with unsaved records?'), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
          await tester.pumpAndSettle();
          expect(find.byType(HomePage), findsOneWidget);
          expect(c.hasPendingSave, true);
          expect(find.textContaining('not fully saved'), findsOneWidget);
          final id = c.engine!.id;
          await expectLater(
            c.start('G1_MEMORY', c.layout!),
            throwsA(isA<StateError>()),
          );
          expect(c.engine!.id, id);
          await c.repository.db.execute('DROP TRIGGER fail_session_write');
          await c.finishSave();
          await tester.pumpAndSettle();
          expect(c.hasPendingSave, false);
          expect(c.saved, true);
          expect((await c.repository.detail(id))!['status'], 'EXITED');
        }
        expect(
          await c.repository.db.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        var homeDisplay = await c.platform.call('getCapabilities');
        for (
          var i = 0;
          i < 50 && homeDisplay['status_bar_hidden'] == true;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
          homeDisplay = await c.platform.call('getCapabilities');
        }
        expect(homeDisplay['training_fullscreen'], false);
        expect(homeDisplay['status_bar_hidden'], false);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump();
      final directory = File(c.repository.db.path).parent;
      await c.repository.db.close();
      await directory.delete(recursive: true);
    },
  );
}
