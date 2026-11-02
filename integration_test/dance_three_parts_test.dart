import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/features/dance_page.dart';
import 'package:piano_practice/features/dance_result_page.dart';
import 'package:piano_practice/platform/platform_service.dart';
import 'package:piano_practice/ui/qin_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chinese dance assets, part switching, completion and persistence',
    (tester) async {
      if (!const bool.fromEnvironment('DANCE_FLOW_TEST_PACKAGE')) {
        throw StateError('Use the dedicated dance QA package');
      }
      final caps = await PlatformService().call('getCapabilities');
      final repo = PracticeRepository();
      final folder = Directory('${caps['storage_path']}/dance-flow-${uuid()}');
      await folder.create();
      await repo.open(folder.path, 'zh-Hans');
      final c = AppController(repository: repo)..initialized = true;
      for (var i = 0; i < chineseDanceCourse.parts.length; i++) {
        final video = VideoPlayerController.asset(
          chineseDanceCourse.parts[i].asset,
        );
        try {
          await video.initialize();
          expect(video.value.isInitialized, true);
          expect(video.value.size, const Size(1280, 720));
          final expected = [78, 388, 28][i];
          expect(
            video.value.duration.inSeconds,
            inInclusiveRange(expected - 1, expected + 1),
          );
          await video.play();
          await Future<void>.delayed(const Duration(milliseconds: 800));
          expect((await video.position)!.inMilliseconds, greaterThan(0));
          await video.pause();
          expect(video.value.hasError, false);
          debugPrint(
            'DANCE_PART_${i + 1}: ${video.value.duration.inMilliseconds}ms ${video.value.size}',
          );
        } finally {
          await video.dispose();
        }
      }
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: qinTheme(highContrast: false),
          home: DancePage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('dance-preparation-0.1.54');
      await tester.tap(find.byKey(const ValueKey('start-dance')));
      Future<void> waitVideo() async {
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byType(VideoPlayer).evaluate().isNotEmpty) return;
        }
        fail('Video did not initialize');
      }

      await waitVideo();
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
      await binding.takeScreenshot('dance-player-0.1.54');
      await tester.tap(find.byTooltip('音量'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('dance-volume-panel')), findsOneWidget);
      await binding.takeScreenshot('dance-volume-0.1.54');
      await tester.tap(find.byKey(const ValueKey('dance-rate')));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('dance-speed-0.1.54');
      await tester.tap(find.text('1.25x'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('dance-fullscreen')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('dance-fullscreen-back')),
        findsOneWidget,
      );
      await binding.takeScreenshot('dance-fullscreen-0.1.54');
      await tester.tap(find.byKey(const ValueKey('dance-fullscreen-back')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('dance-exit-0.1.54');
      final continueRect = tester.getRect(
        find.byKey(const ValueKey('continue-dance')),
      );
      final exitRect = tester.getRect(
        find.byKey(const ValueKey('confirm-exit-dance')),
      );
      expect(continueRect.center.dy, closeTo(exitRect.center.dy, 1));
      await tester.tap(find.byKey(const ValueKey('continue-dance')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('dance-part-1')));
      await waitVideo();
      expect(
        tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller
            .dataSource,
        chineseDanceCourse.parts[1].asset,
      );
      await tester.tap(find.byKey(const ValueKey('dance-part-0')));
      await waitVideo();
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      await controller.seekTo(
        controller.value.duration - const Duration(milliseconds: 300),
      );
      await controller.play();
      for (
        var i = 0;
        i < 80 &&
            find.byKey(const ValueKey('dance-next-part')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('第一部分已播放结束'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dance-next-part')));
      await waitVideo();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('finish-dance')));
      for (var i = 0; i < 80 && find.text('已保存训练记录').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(DanceResultPage), findsOneWidget);
      expect(find.text('已保存训练记录'), findsOneWidget);
      await binding.takeScreenshot('dance-result-0.1.54');
      final records = await TrainingScheduleRepository(
        repo.db,
        repo.profile['profile_id'] as String,
      ).dances();
      expect(records, hasLength(1));
      expect(records.single['content_id'], chineseDanceCourse.id);
      expect(records.single['parts'], hasLength(3));
      expect(records.single['active_ms'], greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      c.dispose();
      await repo.db.close();
    },
  );
}
