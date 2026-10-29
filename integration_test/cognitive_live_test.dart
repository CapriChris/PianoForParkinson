import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/training_page.dart';

import 'live_clock_flow_test.dart' show tapNote, awaitResponse;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real clock and SoundPool: G2/G3 responsive holds, pauses, first save and back',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'cognitive-live-${uuid()}');
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
      for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => TrainingPage(c: c, taskId: task),
              ),
            );
        await tester.pump();
        await awaitResponse(tester, c);
        final attempt = c.engine!.attempts.last['attempt_id'],
            target = canonical(c.engine!.target);
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byKey(const ValueKey('pause-toggle')));
        for (var i = 0; i < 100 && c.engine!.phase == 'paused'; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(c.engine!.attempts.last['attempt_id'], attempt);
        expect(canonical(c.engine!.target), target);
        if (c.engine!.target['trial_type'] == 'GO') {
          await tapNote(tester, c, c.engine!.expected.single);
        }
        for (var i = 0; i < 500 && c.engine!.completed == 0; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(c.engine!.completed, 1);
        await c.flush();
        expect(c.storageError, isNull);
        final valid = c.engine!.attempts.singleWhere(
          (a) => a['validity'] == 'VALID',
        );
        expect(
          valid['active_duration_us'],
          c.engine!.responsiveControls && valid['result']['trial_type'] == 'GO'
              ? allOf(
                  greaterThanOrEqualTo(400000),
                  lessThanOrEqualTo(c.engine!.responseWindowUs),
                )
              : c.engine!.responseWindowUs,
        );
        expect(
          valid['result']['outcome'],
          valid['result']['trial_type'] == 'GO' ? 'HIT' : 'CORRECT_WITHHOLD',
        );
        expect(
          await c.repository.db.query(
            'attempts',
            where: "session_id=? AND validity='VALID'",
            whereArgs: [c.engine!.id],
          ),
          hasLength(1),
        );
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 300 && (!c.saved || find.byType(HomePage).evaluate().isEmpty);
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(c.storageError, isNull);
        expect(find.byType(HomePage), findsOneWidget);
        expect(c.saved, true);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
