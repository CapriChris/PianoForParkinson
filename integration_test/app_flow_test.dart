import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/cognitive_tasks.dart';

Future<void> response(
  WidgetTester tester,
  AppController c,
  ManualClock clock,
) async {
  for (var i = 0; i < 2500; i++) {
    if (c.engine?.phase == 'response') return;
    if (c.engine?.phase == 'paused') {
      if (c.engine!.pauseReason == 'E_LAYOUT_CHANGED') {
        await c.resume();
      } else {
        throw StateError(
          'Unexpected pause ${c.engine!.pauseReason} / ${c.storageError}',
        );
      }
    }
    clock.now += 20000;
    await tester.pump(const Duration(milliseconds: 20));
  }
  throw StateError('Training did not reach a response: ${c.engine?.phase}');
}

Future<void> key(
  WidgetTester tester,
  AppController c,
  ManualClock clock,
  int note,
) async {
  final rect = c.layout!['keys'][note]['hit_rect'] as List;
  final gesture = await tester.startGesture(
    Offset((rect[0] + rect[2] / 2) / 1000, (rect[1] + rect[3] / 2) / 1000),
  );
  if (c.engine!.requiresHold) {
    clock.now += 420000;
    await tester.pump(const Duration(milliseconds: 20));
  }
  await gesture.up();
  clock.now += 20000;
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home to complete G1 and S1, saved results and history', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(
      clock: clock,
      databaseSubdirectory: 'flow-${uuid()}',
    );
    await c.initialize();
    expect(c.error, isNull);
    await c.repository.clear();
    await c.updateSettings(
      locale: 'en',
      onboard: true,
      values: {...c.settings, 'sound_enabled': false},
    );
    await tester.pumpWidget(PianoApp(controller: c));
    await tester.pumpAndSettle();
    for (final task in ['G1_MEMORY', 'S1_GUIDED']) {
      final practice = find.descendant(
        of: find.widgetWithText(PracticeCard, taskTitle(task, false)),
        matching: find.byType(FilledButton),
      );
      await tester.scrollUntilVisible(
        practice,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(practice), alignment: .5);
      await tester.pumpAndSettle();
      expect(practice.hitTestable(), findsOneWidget);
      await tester.tap(practice);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start practice'));
      await tester.pump(const Duration(seconds: 1));
      for (var block = 0; block < 2; block++) {
        final trials = task == 'G1_MEMORY' ? 3 : 8;
        for (var trial = 0; trial < trials; trial++) {
          await response(tester, c, clock);
          for (final note in List<int>.from(c.engine!.expected)) {
            await key(tester, c, clock, note);
          }
          clock.now += 400000;
          await tester.pump(const Duration(milliseconds: 400));
        }
        if (block == 0) {
          await tester.ensureVisible(find.text('Next block'));
          await tester.tap(find.text('Next block'));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      for (var i = 0; i < 100 && !c.saved; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.storageError, isNull);
      expect(c.saved, true);
      expect(c.engine!.finishStatus, 'COMPLETED');
      await tester.pumpAndSettle();
      expect(find.text('You finished this practice'), findsOneWidget);
      final id = c.engine!.id;
      final record = await c.repository.detail(id);
      expect(record!['status'], 'COMPLETED');
      expect(
        await c.repository.db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, 'Home'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(ResultPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Home'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(c.history.length, 2);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump();
    final directory = File(c.repository.db.path).parent;
    expect(directory.path.endsWith('/${c.databaseSubdirectory}'), true);
    await c.repository.db.close();
    await directory.delete(recursive: true);
  });
}
