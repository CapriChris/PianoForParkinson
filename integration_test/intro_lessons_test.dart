import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/intro_lessons.dart';
import 'package:piano_practice/features/intro_lessons_page.dart';
import 'package:piano_practice/features/spoken_text.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'lessons persist only completion, survive reopen and clear independently of settings',
    (tester) async {
      final lessonClock = ManualClock();
      final c = AppController(
        clock: lessonClock,
        databaseSubdirectory: 'lessons-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
      await c.updateSettings(
        locale: 'zh-Hans',
        onboard: true,
        values: {'high_contrast': true},
      );
      final path =
          '${c.capabilities['storage_path']}/${c.databaseSubdirectory}';
      addTearDown(() async {
        c.dispose();
        if (c.repository.db.isOpen) await c.repository.db.close();
        final directory = Directory(path).absolute;
        final parent = Directory(c.capabilities['storage_path'] as String)
            .absolute
            .path;
        if (!directory.path.startsWith('$parent${Platform.pathSeparator}') ||
            !directory.path.endsWith(c.databaseSubdirectory!)) {
          throw StateError('Invalid isolated cleanup path');
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      const capture = bool.fromEnvironment('CAPTURE_LESSONS');
      if (capture) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('qinban-0.1.13-home');
      }
      Future<void> tap(String label) async {
        if (find.text(label).evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text(label),
            180,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await tap('打开教学');
      if (capture) await binding.takeScreenshot('qinban-0.1.13-lessons');
      await tap('打开教学');
      await tap('退出教学');
      expect(await c.repository.completedLessons(), isEmpty);
      for (var i = 0; i < IntroLesson.all.length; i++) {
        final card = find.byKey(ValueKey(IntroLesson.all[i].id));
        if (card.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            card,
            180,
            scrollable: find.byType(Scrollable).last,
          );
        }
        final button = find.descendant(of: card, matching: find.text('打开教学'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        if (IntroLesson.all[i].id == 'T3') {
          var display = await c.platform.call('getCapabilities');
          for (var n = 0; n < 30 && display['status_bar_hidden'] != true; n++) {
            await tester.pump(const Duration(milliseconds: 20));
            display = await c.platform.call('getCapabilities');
          }
          expect(display['status_bar_hidden'], true);
        }
        expect(find.byIcon(Icons.close), findsNothing);
        for (var page = 0; page < 3; page++) {
          await tap('观看示范');
          if (capture && i == 0 && page == 1) {
            lessonClock.now += 200000;
            await tester.pump(const Duration(milliseconds: 40));
            await binding.takeScreenshot('qinban-0.1.13-T1-held');
          }
          lessonClock.now += 500000;
          await tester.pump(const Duration(milliseconds: 500));
          if (capture && i != 1) {
            if (find.byType(SpokenText).evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                find.byType(SpokenText),
                -180,
                scrollable: find.byType(Scrollable).last,
              );
            }
            await tester.ensureVisible(find.byType(SpokenText));
            await tester.pump();
            await binding.takeScreenshot(
              'qinban-0.1.13-${IntroLesson.all[i].id}-page-${page + 1}',
            );
          }
          await tap('停止示范');
          await tap(page == 2 ? '完成教学' : '下一页');
        }
        expect(
          await c.repository.completedLessons(),
          contains(IntroLesson.all[i].id),
        );
        if (IntroLesson.all[i].id == 'T3') {
          var display = await c.platform.call('getCapabilities');
          for (
            var n = 0;
            n < 30 && display['training_fullscreen'] == true;
            n++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            display = await c.platform.call('getCapabilities');
          }
          expect(display['training_fullscreen'], false);
        }
      }
      expect(find.byType(IntroLessonsPage), findsOneWidget);
      expect(c.allIntroLessonsCompleted, true);
      expect(find.text('跳过，返回练习'), findsNothing);
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => InstructionPage(c: c, taskId: 'S1_GUIDED'),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('查看入门教学（可选）'), findsNothing);
      expect(find.byTooltip('播放语音说明'), findsOneWidget);
      if (capture) {
        await binding.takeScreenshot('qinban-0.1.13-instruction-complete');
      }
      final db = c.repository.db;
      final rows = await db.query('tutorial_progress');
      expect(rows, hasLength(3));
      expect(
        rows.every(
          (r) =>
              r['completed'] == 1 && r['lesson_version'] == IntroLesson.version,
        ),
        true,
      );
      for (final table in [
        'sessions',
        'events',
        'attempts',
        'summaries',
        'profile_task_state',
      ]) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      await expectLater(
        c.repository.completeLesson('INVALID'),
        throwsArgumentError,
      );
      await c.repository.completeLesson('T1');
      expect(await db.query('tutorial_progress'), hasLength(3));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
      final restarted = AppController(
        databaseSubdirectory: c.databaseSubdirectory,
      );
      await restarted.initialize();
      expect(restarted.error, isNull);
      final reopened = restarted.repository;
      try {
        expect(restarted.allIntroLessonsCompleted, true);
        expect(await reopened.completedLessons(), {'T1', 'T2', 'T3'});
        final settings = canonical(reopened.settings);
        await restarted.clearPracticeRecords();
        expect(restarted.allIntroLessonsCompleted, false);
        expect(await reopened.completedLessons(), isEmpty);
        expect(canonical(reopened.settings), settings);
        expect(reopened.profile['locale'], 'zh-Hans');
      } finally {
        restarted.dispose();
        await reopened.db.close();
      }
    },
  );
}
