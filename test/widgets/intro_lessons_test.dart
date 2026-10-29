import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/intro_lessons.dart';
import 'package:piano_practice/features/intro_lessons_page.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/lesson_beat_timeline.dart';

class LessonRepository extends PracticeRepository {
  final completed = <String>{};
  bool failSave = false, failRead = false;
  @override
  Future<Set<String>> completedLessons() async {
    if (failRead) throw StateError('read failed');
    return {...completed};
  }

  @override
  Future<void> completeLesson(String id) async {
    if (failSave) throw StateError('save failed');
    completed.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController c;
  late LessonRepository repository;
  late ManualClock clock;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    var voice = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            calls.add(call);
            return {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': {'voice_id': ++voice},
            };
          },
        );
    repository = LessonRepository();
    clock = ManualClock();
    c = AppController(clock: clock, repository: repository)
      ..initialized = true
      ..audioReady = true;
    repository.profile = {
      'profile_id': 'test',
      'locale': 'zh-Hans',
      'mode': 'ASSIST',
      'onboarding_completed': 1,
      'settings_json': jsonEncode({
        'sound_enabled': true,
        'gain_permille': 850,
        'speech_enabled': true,
        'speech_gain_permille': 1000,
      }),
    };
  });
  tearDown(() => c.dispose());

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        locale: Locale(c.chinese ? 'zh' : 'en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => child)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        180,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'brand and optional lessons reachable from home and task instructions',
    (tester) async {
      await tester.pumpWidget(PianoApp(controller: c));
      expect(find.text('琴伴'), findsOneWidget);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '琴伴');
      await tap(tester, '打开教学');
      expect(find.byType(IntroLessonsPage), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => InstructionPage(c: c, taskId: 'S1_GUIDED'),
            ),
          );
      await tester.pumpAndSettle();
      await tap(tester, '查看入门教学（可选）');
      expect(find.byType(IntroLessonsPage), findsOneWidget);
      expect(c.engine, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'exit skips completion; all lessons complete and can be repeated',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.first));
      await tap(tester, '退出教学');
      expect(repository.completed, isEmpty);
      for (final lesson in IntroLesson.all) {
        await show(tester, IntroLessonPage(c: c, lesson: lesson));
        await tap(tester, '下一页');
        await tap(tester, '上一页');
        expect(find.text('1 / 3'), findsOneWidget);
        await tap(tester, '下一页');
        await tap(tester, '下一页');
        await tap(tester, '完成教学');
        expect(repository.completed, contains(lesson.id));
        expect(c.engine, isNull);
      }
      await show(tester, IntroLessonsPage(c: c));
      expect(find.text('已完成 · 可以重看'), findsWidgets);
      await tap(tester, '打开教学');
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'read failure allows learning and completion save failure can retry',
    (tester) async {
      repository.failRead = true;
      await show(tester, IntroLessonsPage(c: c));
      expect(find.text('完成标记读取失败，可以继续学习。'), findsOneWidget);
      await tap(tester, '打开教学');
      await tap(tester, '下一页');
      await tap(tester, '下一页');
      repository.failSave = true;
      await tap(tester, '完成教学');
      expect(find.textContaining('完成标记未保存'), findsOneWidget);
      expect(repository.completed, isEmpty);
      repository.failSave = false;
      repository.failRead = false;
      await tap(tester, '完成教学');
      expect(find.byType(IntroLessonsPage), findsOneWidget);
      expect(repository.completed, {'T3'});
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rhythm alternates play and wait, locks example input and stops in background',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.last));
      await tap(tester, '下一页');
      await tap(tester, '下一页');
      await tap(tester, '观看示范');
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
        true,
      );
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
        0,
      );
      clock.now += 1500000;
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('等待'), findsNWidgets(2));
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
        isNull,
      );
      clock.now += 1500000;
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
        0,
      );
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
        false,
      );
      final plays = calls.where((c) => c.method == 'playNote').length;
      clock.now += 10000000;
      await tester.pump(const Duration(seconds: 10));
      expect(calls.where((c) => c.method == 'playNote').length, plays);
      expect(repository.completed, isEmpty);
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pitch example rises; hold guide and speech work without creating a session',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all[1]));
      await tap(tester, '下一页');
      await tap(tester, '下一页');
      await tester.tap(find.byTooltip('播放语音说明'));
      await tester.pumpAndSettle();
      expect(find.text('朗读说明'), findsNothing);
      expect(calls.where((c) => c.method == 'speakLocal'), hasLength(1));
      await tap(tester, '观看示范');
      for (var step = 1; step <= 3; step++) {
        clock.now += 1500000;
        await tester.pump(const Duration(milliseconds: 40));
      }
      final notes = calls
          .where((c) => c.method == 'playNote')
          .map((c) => (c.arguments as Map)['note_id'])
          .toList();
      expect(notes, [0, 1, 2]);
      await tester.ensureVisible(find.byType(PianoKeyboard));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PianoKeyboard)),
      );
      clock.now += 400000;
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<KeyDurationGuide>(find.byType(KeyDurationGuide)).progress,
        1,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.engine, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'audio focus interruption stops a demonstration without restarting it',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.first));
      await tap(tester, '观看示范');
      c.previewInterruptions.value++;
      await tester.pumpAndSettle();
      final playCount = calls.where((c) => c.method == 'playNote').length;
      clock.now += 10000000;
      await tester.pump(const Duration(seconds: 10));
      expect(calls.where((c) => c.method == 'playNote').length, playCount);
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
        false,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'key example visibly releases after 400 ms before the next press',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.first));
      await tap(tester, '下一页');
      await tap(tester, '下一页');
      await tap(tester, '观看示范');
      final randomKey = tester
          .widget<PianoKeyboard>(find.byType(PianoKeyboard))
          .highlighted;
      expect(randomKey, inInclusiveRange(0, 2));
      clock.now += 400000;
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
        isNull,
      );
      clock.now += 1100000;
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
        randomKey,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('short and full touch examples display different hold lengths', (
    tester,
  ) async {
    await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.first));
    expect(find.byIcon(Icons.close), findsNothing);
    await tap(tester, '观看示范');
    clock.now += 200000;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
      isNull,
    );
    expect(
      tester.widget<KeyDurationGuide>(find.byType(KeyDurationGuide)).progress,
      inInclusiveRange(.25, .5),
    );
    await tap(tester, '下一页');
    await tap(tester, '观看示范');
    clock.now += 200000;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).highlighted,
      isNotNull,
    );
    final keyColors = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(PianoKeyboard),
            matching: find.byType(Container),
          ),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.color);
    expect(
      keyColors.where((color) => color == const Color(0xffc6ddbd)),
      hasLength(1),
    );
    final plays = calls.where((call) => call.method == 'playNote').length;
    await tester.tap(find.byType(PianoKeyboard));
    await tester.pump();
    expect(calls.where((call) => call.method == 'playNote').length, plays);
    clock.now += 200000;
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      tester.widget<KeyDurationGuide>(find.byType(KeyDurationGuide)).progress,
      1,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'first rhythm page has only metronome; second plays all beats and retains final progress',
    (tester) async {
      await show(tester, IntroLessonPage(c: c, lesson: IntroLesson.all.last));
      expect(find.byType(PianoKeyboard), findsNothing);
      await tap(tester, '观看示范');
      for (var step = 0; step < 4; step++) {
        clock.now += 1500000;
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(
        calls
            .where((c) => c.method == 'playNote')
            .map((c) => (c.arguments as Map)['note_id']),
        [7, 7, 7, 7],
      );
      expect(
        tester
            .widget<LessonBeatTimeline>(find.byType(LessonBeatTimeline))
            .progress,
        1,
      );
      await tap(tester, '下一页');
      expect(find.text('等待'), findsNothing);
      expect(find.text('弹奏'), findsNWidgets(4));
      calls.clear();
      await tap(tester, '观看示范');
      for (var step = 0; step < 4; step++) {
        clock.now += 1500000;
        await tester.pump(const Duration(milliseconds: 40));
      }
      final notes = calls
          .where((c) => c.method == 'playNote')
          .map((c) => (c.arguments as Map)['note_id'])
          .toList();
      expect(notes.where((n) => n == 7), hasLength(4));
      expect(notes.where((n) => n == 0), hasLength(4));
      expect(
        tester
            .widget<LessonBeatTimeline>(find.byType(LessonBeatTimeline))
            .progress,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'completing all lessons removes links in every task, keeps home lessons and survives progress reload',
    (tester) async {
      await c.completeIntroLesson('T1');
      await c.completeIntroLesson('T2');
      await show(tester, InstructionPage(c: c, taskId: 'S1_GUIDED'));
      expect(find.text('查看入门教学（可选）'), findsOneWidget);
      await c.completeIntroLesson('T3');
      await tester.pumpAndSettle();
      expect(find.text('查看入门教学（可选）'), findsNothing);
      await c.refreshIntroLessonProgress();
      for (final id in [
        'G1_MEMORY',
        'G2_INHIBITION',
        'G3_SWITCH',
        'S1_GUIDED',
        'S2_RHYTHM',
        'M1_ALTERNATE',
      ]) {
        await show(tester, InstructionPage(c: c, taskId: id));
        expect(find.text('查看入门教学（可选）'), findsNothing);
        await tester.tap(find.byTooltip('播放语音说明'));
        await tester.pumpAndSettle();
        final spokenBefore = calls
            .where((c) => c.method == 'speakLocal')
            .length;
        await tap(tester, '试按琴键');
        expect(
          calls.where((c) => c.method == 'speakLocal').length,
          spokenBefore,
        );
        expect(find.text('试按 · 不计入记录'), findsOneWidget);
      }
      await tester.pumpWidget(PianoApp(controller: c));
      expect(find.text('入门教学'), findsWidgets);
      await show(tester, IntroLessonsPage(c: c));
      expect(find.text('跳过，返回练习'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(360, 640),
    const Size(800, 1280),
    const Size(800, 360),
  ]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('lesson layouts $size $locale scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          repository.profile['locale'] = locale;
          for (final lesson in IntroLesson.all) {
            await show(tester, IntroLessonPage(c: c, lesson: lesson));
            for (var page = 0; page < 3; page++) {
              expect(tester.takeException(), isNull);
              await tap(
                tester,
                page == 2
                    ? c.text('完成教学', 'Complete lesson')
                    : c.text('下一页', 'Next page'),
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
  for (final size in [const Size(800, 360), const Size(914, 411)]) {
    for (final locale in ['zh-Hans', 'en']) {
      testWidgets(
        'T3 stacked controls stay visible; medium landscape fits $size $locale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(bottom: 24);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPadding);
          repository.profile['locale'] = locale;
          await tester.pumpWidget(PianoApp(controller: c));
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      IntroLessonPage(c: c, lesson: IntroLesson.all.last),
                ),
              );
          await tester.pumpAndSettle();
          for (var page = 0; page < 3; page++) {
            final viewport = tester.state<ScrollableState>(
              find.byType(Scrollable).last,
            );
            expect(
              viewport.position.maxScrollExtent,
              size.height >= 400 ? 0 : lessThanOrEqualTo(56),
            );
            final action = find.text(
              page == 2
                  ? c.text('完成教学', 'Complete lesson')
                  : c.text('下一页', 'Next page'),
            );
            expect(
              tester.getBottomLeft(find.byType(LessonBeatTimeline)).dy,
              lessThanOrEqualTo(tester.getTopLeft(action).dy),
            );
            if (page > 0) {
              expect(
                tester.getBottomLeft(action).dy,
                lessThan(tester.getTopLeft(find.byType(PianoKeyboard)).dy),
              );
              expect(
                tester.getBottomLeft(action).dy,
                lessThanOrEqualTo(size.height - 24),
              );
              if (size.height >= 400) {
                expect(
                  tester.getBottomLeft(find.byType(PianoKeyboard)).dy,
                  lessThanOrEqualTo(size.height - 24),
                );
              }
            }
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(c.text('观看示范', 'Watch example')));
            await tester.pump(const Duration(milliseconds: 40));
            expect(
              viewport.position.maxScrollExtent,
              size.height >= 400 ? 0 : lessThanOrEqualTo(56),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(c.text('停止示范', 'Stop example')));
            await tester.pumpAndSettle();
            await tester.tap(action);
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
