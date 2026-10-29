import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/features/intro_lessons_page.dart';
import 'package:piano_practice/domain/intro_lessons.dart';

import 'intro_lessons_test.dart' show LessonRepository;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final id in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'S1_GUIDED',
    'S2_RHYTHM',
    'M1_ALTERNATE',
    'M2_DUAL_ZONE',
  ]) {
    testWidgets(
      '$id speech stops on back, cover and background, never restarts',
      (tester) async {
        bool speaking = false;
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('piano_training/platform/v1'),
              (call) async {
                calls.add(call);
                if (call.method == 'speakLocal') speaking = true;
                if (call.method == 'stopSpeech') speaking = false;
                return {
                  'ok': true,
                  'request_id': (call.arguments as Map)['request_id'],
                  'data': {},
                };
              },
            );
        final repo = LessonRepository();
        repo.profile = {
          'locale': 'zh-Hans',
          'mode': 'ASSIST',
          'onboarding_completed': 1,
          'settings_json': '{"speech_enabled":true,"speech_gain_permille":1000,"sound_enabled":false,"gain_permille":0}',
        };
        final c = AppController(repository: repo)..initialized = true;
        await tester.pumpWidget(PianoApp(controller: c));
        final nav = tester.state<NavigatorState>(find.byType(Navigator));
        for (final action in ['back', 'cover', 'background']) {
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => InstructionPage(c: c, taskId: id),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('播放语音说明'));
          await tester.pumpAndSettle();
          expect(speaking, true);
          if (action == 'back') {
            nav.pop();
          } else if (action == 'cover') {
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other page')),
              ),
            );
          } else {
            c.didChangeAppLifecycleState(AppLifecycleState.paused);
          }
          await tester.pumpAndSettle();
          expect(speaking, false);
          final count = calls.where((c) => c.method == 'speakLocal').length;
          if (action == 'cover') {
            nav.pop();
            await tester.pumpAndSettle();
          }
          if (action == 'background') {
            c.didChangeAppLifecycleState(AppLifecycleState.resumed);
          }
          await tester.pumpAndSettle();
          expect(calls.where((c) => c.method == 'speakLocal').length, count);
          if (action != 'back') {
            nav.pop();
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
  testWidgets(
    'rhythm lesson requests landscape, four beat cells stay on one row and highlight follows progress',
    (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orientations = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              orientations.add(call.arguments);
            }
            return null;
          });
      final c = AppController(repository: LessonRepository())
        ..initialized = true;
      c.repository.profile = {
        'locale': 'en',
        'settings_json': '{"sound_enabled":false,"gain_permille":0}',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: IntroLessonPage(c: c, lesson: IntroLesson.all.last),
        ),
      );
      await tester.pumpAndSettle();
      expect(orientations.first, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      final positions = [
        for (var i = 1; i <= 4; i++) tester.getTopLeft(find.text('$i')),
      ];
      expect(positions.map((p) => p.dy).toSet().length, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
