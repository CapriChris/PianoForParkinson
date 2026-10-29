import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/piece_sheet_preview.dart';
import 'package:piano_practice/features/piece_continuous_score.dart';
import 'package:piano_practice/features/piece_playback_keys.dart';
import 'package:piano_practice/features/key_press_feedback.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/features/song_library_page.dart';
import 'package:piano_practice/features/key_duration_guide.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> remove(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> slideTempo(WidgetTester tester, {required bool toMaximum}) async {
  final finder = find.byKey(const ValueKey('piece-tempo'));
  await scrollTo(tester, finder, -120);
  final rect = tester.getRect(finder);
  await tester.tapAt(
    Offset(toMaximum ? rect.right - 24 : rect.left + 24, rect.center.dy),
  );
  await frames(tester);
}

Future<void> scrollTo(WidgetTester tester, Finder target, double delta) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
}

void main() {
  testWidgets('all available piece keys fit on one row at phone widths', (
    tester,
  ) async {
    final c = AppController(repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(320, 640), 'zh-Hans', 2, c);
    await tester.runAsync(c.content.load);
    for (final piece in c.content.pieces) {
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: PiecePlaybackKeys(piece: piece, active: const {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rects = [
        for (var i = 0; i < piece.keyCount; i++)
          tester.getRect(find.byKey(ValueKey('playback-feedback-$i'))),
      ];
      expect(rects.map((r) => r.top).toSet(), hasLength(1), reason: piece.id);
      expect(
        rects.last.right - rects.first.left,
        lessThanOrEqualTo(280.01),
        reason: piece.id,
      );
      expect(tester.takeException(), isNull);
    }
    await remove(tester);
  });

  testWidgets('continuous score preserves beat spacing and pickup barlines', (
    tester,
  ) async {
    final c = AppController(repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    await tester.runAsync(c.content.load);
    for (final piece in c.content.pieces) {
      final g = ContinuousScoreLayout(piece, 300);
      for (final note in piece.notes) {
        expect(
          g.rect(note).width,
          closeTo(
            note.ticks * ContinuousScoreLayout.beatWidth / piece.ticksPerBeat,
            .001,
          ),
          reason: piece.id,
        );
      }
      if (g.barTicks.isNotEmpty) {
        expect(
          g.barTicks.first,
          piece.pickupTicks > 0 ? piece.pickupTicks : piece.barTicks,
        );
        for (var i = 1; i < g.barTicks.length; i++) {
          expect(g.barTicks[i] - g.barTicks[i - 1], piece.barTicks);
        }
      }
    }
  });

  for (final locale in ['zh-Hans', 'en']) {
    for (final size in [const Size(360, 640), const Size(800, 360)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'picker opens preparation without a keyboard $locale $size $scale',
          (tester) async {
            final c = AppController(repository: MemoryPreferences());
            addTearDown(c.dispose);
            mocks(tester, size, locale, scale, c);
            await tester.runAsync(c.content.load);
            await tester.pumpWidget(
              MaterialApp(
                theme: qinTheme(highContrast: false),
                home: PianoPiecesPage(c: c),
              ),
            );
            await tester.pumpAndSettle();
            final title = locale == 'zh-Hans' ? '欢乐颂' : 'Ode to Joy';
            await scrollTo(tester, find.text(title), 150);
            await tester.pumpAndSettle();
            await tester.tap(find.text(title));
            await tester.pumpAndSettle();
            expect(find.byType(PianoPiecePage), findsOneWidget);
            expect(find.byType(PianoKeyboard), findsNothing);
            await scrollTo(
              tester,
              find.byKey(const ValueKey('piece-tempo')),
              120,
            );
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('piece-tempo')), findsOneWidget);
            final slider = tester.widget<Slider>(
              find.byKey(const ValueKey('piece-tempo')),
            );
            expect(slider.value, 60);
            expect(
              slider.semanticFormatterCallback!(60),
              locale == 'zh-Hans' ? '60 拍/分钟' : '60 BPM',
            );
            expect(
              find.text(c.content.pieces.first.description(locale)),
              findsNothing,
            );
            expect(find.textContaining('音符从右向左移动'), findsNothing);
            expect(find.byType(PieceSheetPreview), findsOneWidget);
            expect(find.byType(PieceContinuousScore), findsOneWidget);
            await scrollTo(
              tester,
              find.byKey(const ValueKey('piece-audition')),
              120,
            );
            await Scrollable.ensureVisible(
              tester.element(find.byKey(const ValueKey('piece-audition'))),
              alignment: .1,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('piece-audition')));
            await frames(tester);
            expect(find.text(locale == 'en' ? 'Pause' : '暂停'), findsOneWidget);
            expect(find.byKey(const ValueKey('audition-seek')), findsOneWidget);
            expect(
              find.byKey(const ValueKey('enter-performance')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await remove(tester);
          },
        );
      }
    }
  }

  for (final size in [const Size(640, 300), const Size(800, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'landscape performance shows notes and controls only $size $scale',
        (tester) async {
          final clock = ManualClock();
          final c = AppController(
            clock: clock,
            repository: MemoryPreferences(),
          );
          addTearDown(c.dispose);
          mocks(tester, size, 'zh-Hans', scale, c);
          await tester.runAsync(c.content.load);
          await tester.pumpWidget(
            MaterialApp(
              theme: qinTheme(highContrast: scale == 2),
              home: PianoPerformancePage(
                c: c,
                piece: c.content.pieces.first,
                tempo: 60,
              ),
            ),
          );
          await frames(tester);
          expect(find.byType(AppBar), findsNothing);
          expect(find.byType(DropdownButton<int>), findsNothing);
          expect(find.byType(KeyDurationGuide), findsNothing);
          expect(find.byType(ScrollingScore), findsOneWidget);
          expect(
            tester
                .widgetList<Text>(find.byType(Text))
                .every((t) => RegExp(r'^[1-5]$').hasMatch(t.data ?? '')),
            isTrue,
          );
          final keyboard = tester.getRect(find.byType(PianoKeyboard));
          final p = tester
              .widget<ScrollingScore>(find.byType(ScrollingScore))
              .player;
          expect(p.mode, ScrollPieceMode.running);
          clock.now = 4500000;
          await tester.pump(const Duration(milliseconds: 16));
          expect(p.currentIndex, 0);
          expect(tester.getRect(find.byType(PianoKeyboard)), keyboard);
          await tester.tap(find.byKey(const ValueKey('performance-pause')));
          await tester.pumpAndSettle();
          final frozen = p.positionTick;
          clock.now += 10000000;
          await tester.pump(const Duration(seconds: 10));
          expect(p.positionTick, frozen);
          expect(tester.takeException(), isNull);
          await remove(tester);
        },
      );
    }
  }

  testWidgets(
    'home and previous record open preparation, short tasks exclude Ode',
    (tester) async {
      final c = AppController(repository: MemoryPreferences());
      addTearDown(c.dispose);
      mocks(tester, const Size(360, 640), 'zh-Hans', 1, c);
      await tester.runAsync(c.content.load);
      final old = <String, dynamic>{
        'task_id': 'S1_GUIDED',
        'content_id': 'song-ode-to-joy-001',
      };
      c.history = [
        {...old},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: HomePage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('钢琴曲目'));
      await tester.pumpAndSettle();
      expect(find.byType(PianoPiecesPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(PianoPiecesPage))).pop();
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('再练上次的内容'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('再练上次的内容'));
      await tester.pumpAndSettle();
      expect(find.byType(PianoPiecePage), findsOneWidget);
      expect(find.byType(PianoPerformancePage), findsNothing);
      expect(c.history.single, old);
      await remove(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: SongLibraryPage(c: c, taskId: 'S1_GUIDED'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('欢乐颂'), findsNothing);
      expect(tester.takeException(), isNull);
      await remove(tester);
    },
  );

  testWidgets(
    'chosen tempo preview stops before performance, rotation restores on back',
    (tester) async {
      final clock = ManualClock();
      final c = AppController(clock: clock, repository: MemoryPreferences());
      addTearDown(c.dispose);
      mocks(tester, const Size(360, 640), 'zh-Hans', 1, c);
      final orientations = <dynamic>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemChrome.setPreferredOrientations') {
              orientations.add(call.arguments);
            }
            return null;
          });
      await tester.runAsync(c.content.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPiecePage(c: c, piece: c.content.pieces.first),
        ),
      );
      await tester.pumpAndSettle();
      await slideTempo(tester, toMaximum: true);
      expect(find.text('80 拍/分钟'), findsOneWidget);
      await scrollTo(tester, find.byKey(const ValueKey('piece-audition')), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('piece-audition')));
      await frames(tester);
      expect(find.text('暂停'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('enter-performance')));
      await tester
          .pumpAndSettle(); // Portrait cannot start the moving timeline.
      expect(find.byType(PianoPerformancePage), findsOneWidget);
      tester.view.physicalSize = const Size(800, 360);
      await frames(tester);
      final p = tester
          .widget<ScrollingScore>(find.byType(ScrollingScore))
          .player;
      expect(p.tempo, 80);
      expect(p.mode, ScrollPieceMode.running);
      expect(
        orientations,
        contains(
          equals([
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ]),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('performance-back')));
      await tester.pumpAndSettle();
      expect(find.byType(PianoPiecePage), findsOneWidget);
      expect(find.text('试听'), findsOneWidget);
      expect(orientations.last, contains('DeviceOrientation.portraitUp'));
      expect(tester.takeException(), isNull);
      await remove(tester);
    },
  );

  testWidgets('score can be dragged, auditioned, paused and resumed', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPiecePage(c: c, piece: c.content.pieces.first),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('audition-score-scroll'));
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    await tester.drag(scroll, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await tester.drag(scroll, const Offset(220, 0));
    await tester.pumpAndSettle();
    controller.jumpTo(
      ContinuousScoreLayout.leadBeats * ContinuousScoreLayout.beatWidth,
    );
    await tester.pump();
    final staff = find.byKey(const ValueKey('continuous-score'));
    final painter =
        tester.widget<CustomPaint>(staff).painter! as ContinuousScorePainter;
    final note = c.content.pieces.first.notes[1];
    await tester.tapAt(tester.getTopLeft(staff) + painter.g.rect(note).center);
    await frames(tester);
    final seek = tester.widget<Slider>(
      find.byKey(const ValueKey('audition-seek')),
    );
    expect(seek.value, 1000000);
    expect(
      tester
          .widget<KeyPressFeedback>(
            find.byKey(ValueKey('playback-feedback-${note.key}')),
          )
          .pressed,
      isTrue,
    );
    await scrollTo(tester, find.byKey(const ValueKey('piece-audition')), 120);
    await tester.tap(find.byKey(const ValueKey('piece-audition')));
    await frames(tester);
    expect(find.text('暂停'), findsOneWidget);
    clock.now = 2000000;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byKey(const ValueKey('piece-audition')));
    await frames(tester);
    final frozen = tester
        .widget<Slider>(find.byKey(const ValueKey('audition-seek')))
        .value;
    clock.now += 5000000;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('audition-seek'))).value,
      frozen,
    );
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets(
    'playback scrolls continuously past a fixed line and supports note taps',
    (tester) async {
      final clock = ManualClock();
      final c = AppController(clock: clock, repository: MemoryPreferences());
      addTearDown(c.dispose);
      mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
      await tester.runAsync(c.content.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPiecePage(c: c, piece: c.content.pieces.first),
        ),
      );
      await tester.pumpAndSettle();
      final score = find.byKey(const ValueKey('continuous-score'));
      final guide = find.byKey(const ValueKey('fixed-score-guide'));
      final controller = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('audition-score-scroll')),
          )
          .controller!;
      final guideLeft = tester.getTopLeft(guide).dx;
      final initialScoreLeft = tester.getTopLeft(score).dx;
      final play = find.byKey(const ValueKey('piece-audition'));
      await Scrollable.ensureVisible(tester.element(play), alignment: .2);
      await tester.pumpAndSettle();
      await tester.tap(play);
      await frames(tester);
      clock.now = 1000000;
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.offset, closeTo(ContinuousScoreLayout.beatWidth, .01));
      expect(tester.getTopLeft(guide).dx, closeTo(guideLeft, .01));
      expect(
        tester.getTopLeft(score).dx,
        closeTo(initialScoreLeft - ContinuousScoreLayout.beatWidth, .01),
      );
      clock.now = 2000000;
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        controller.offset,
        closeTo(2 * ContinuousScoreLayout.beatWidth, .01),
      );
      clock.now = 4000000;
      await tester.pump(const Duration(milliseconds: 16));
      final painter =
          tester.widget<CustomPaint>(score).painter! as ContinuousScorePainter;
      final note = c.content.pieces.first.notes.first;
      expect(
        tester.getTopLeft(score).dx + painter.g.rect(note).left,
        closeTo(
          tester.getTopLeft(guide).dx + ContinuousScoreLayout.origin,
          .01,
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(score) + painter.g.rect(note).center,
      );
      await frames(tester);
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('audition-seek')))
            .value,
        0,
      );
      expect(
        controller.offset,
        closeTo(
          ContinuousScoreLayout.leadBeats * ContinuousScoreLayout.beatWidth,
          .01,
        ),
      );
      expect(
        tester
            .widget<KeyPressFeedback>(
              find.byKey(ValueKey('playback-feedback-${note.key}')),
            )
            .pressed,
        isTrue,
      );
      c.previewInterruptions.value++;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await remove(tester);
    },
  );

  testWidgets('dragging during playback seeks and resumes in sync', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    c.repository.profile['settings_json'] = jsonEncode({
      'sound_enabled': true,
      'gain_permille': 600,
    });
    final starts = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            final args = call.arguments as Map;
            if (call.method == 'syncPieceBacking') {
              starts.add(args['position_us'] as int);
            }
            return {
              'ok': true,
              'request_id': args['request_id'],
              'data': {'prepared': true, 'accepted': true},
            };
          },
        );
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPiecePage(c: c, piece: c.content.pieces.first),
      ),
    );
    await tester.pumpAndSettle();
    final play = find.byKey(const ValueKey('piece-audition'));
    await Scrollable.ensureVisible(tester.element(play), alignment: .2);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await frames(tester);
    clock.now = 1000000;
    await tester.pump(const Duration(milliseconds: 16));
    final score = find.byKey(const ValueKey('audition-score-scroll'));
    final controller = tester.widget<SingleChildScrollView>(score).controller!;
    await Scrollable.ensureVisible(tester.element(score), alignment: .15);
    await tester.pump(const Duration(milliseconds: 16));
    final gesture = await tester.startGesture(tester.getCenter(score));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-96, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await frames(tester);
    expect(controller.offset, closeTo(ContinuousScoreLayout.beatWidth + 96, 1));
    expect(starts, hasLength(2));
    expect(starts.first, -4000000);
    final draggedTime =
        -3000000 + 96 * 1000000 / ContinuousScoreLayout.beatWidth;
    expect(starts.last, closeTo(draggedTime, 25000));
    expect(find.text('暂停'), findsOneWidget);
    clock.now = 3000000;
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      controller.offset,
      closeTo(3 * ContinuousScoreLayout.beatWidth + 96, 2),
    );
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('audition-seek'))).value,
      closeTo(draggedTime + 2000000, 25000),
    );
    c.previewInterruptions.value++;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets('pausing during the lead-in resumes the remaining preparation', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    c.repository.profile['settings_json'] = jsonEncode({
      'sound_enabled': true,
      'gain_permille': 600,
    });
    final starts = <int>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            final args = call.arguments as Map;
            if (call.method == 'syncPieceBacking') {
              starts.add(args['position_us'] as int);
            }
            return {
              'ok': true,
              'request_id': args['request_id'],
              'data': {'prepared': true, 'accepted': true},
            };
          },
        );
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPiecePage(c: c, piece: c.content.pieces.first),
      ),
    );
    await tester.pumpAndSettle();
    final play = find.byKey(const ValueKey('piece-audition'));
    await Scrollable.ensureVisible(tester.element(play), alignment: .2);
    await tester.pumpAndSettle();
    await tester.tap(play);
    await frames(tester);
    int visibleTimeline() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('fixed-score-guide')),
                    )
                    .painter!
                as FixedScoreGuidePainter)
            .timeline
            .value;
    expect(visibleTimeline(), -4000000);
    clock.now = 1000000;
    await tester.pump(const Duration(milliseconds: 16));
    expect(visibleTimeline(), -3000000);
    await tester.tap(play);
    await frames(tester);
    clock.now = 6000000;
    await tester.tap(play);
    await frames(tester);
    expect(starts, [-4000000, -3000000]);
    expect(visibleTimeline(), -3000000);
    c.previewInterruptions.value++;
    await tester.pumpAndSettle();
    await remove(tester);
  });

  testWidgets('preview pre-mixes unequal durations and stops on interruption', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(800, 600), 'zh-Hans', 1, c);
    c.repository.profile['settings_json'] = jsonEncode({
      'sound_enabled': true,
      'gain_permille': 600,
    });
    final calls = <({String name, int time})>[];
    List<dynamic> melody = [];
    var voice = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            calls.add((name: call.method, time: clock.now));
            if (call.method == 'preparePieceBacking') {
              melody = (call.arguments as Map)['melody'] as List;
            }
            return {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': call.method == 'playNote'
                  ? {'voice_id': ++voice}
                  : {'prepared': true, 'accepted': true},
            };
          },
        );
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPiecePage(c: c, piece: c.content.pieces.first),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.byKey(const ValueKey('piece-audition')), 120);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('piece-audition'))),
      alignment: .25,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('piece-audition')));
    await frames(tester);
    expect(calls.where((call) => call.name == 'playNote'), isEmpty);
    expect(
      calls.where((call) => call.name == 'syncPieceBacking'),
      hasLength(1),
    );
    expect(melody, hasLength(61)); // Rest is silent in the pre-mixed audio.
    expect(melody[12]['duration_us'], 1500000);
    expect(melody[13]['duration_us'], 500000);
    expect(melody[14]['duration_us'], 2000000);
    clock.now = 4000000;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    for (final n in c.content.pieces.first.notes) {
      clock.now = 4000000 + n.endTick * 250000;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
    }
    final plays = calls.where((call) => call.name == 'playNote').toList();
    final stops = calls.where((call) => call.name == 'stopVoice').toList();
    expect(
      calls.where((call) => call.name == 'syncPieceBacking').first.time,
      0,
    );
    expect(calls.where((call) => call.name == 'pausePieceBacking'), isNotEmpty);
    expect(plays, isEmpty);
    expect(stops, isEmpty);
    await tester.tap(find.byKey(const ValueKey('piece-audition')));
    await frames(tester);
    c.previewInterruptions.value++;
    await tester.pumpAndSettle();
    expect(find.text('试听'), findsOneWidget);
    final playCount = calls.where((call) => call.name == 'playNote').length;
    clock.now += 10000000;
    await tester.pump(const Duration(seconds: 10));
    expect(
      calls.where((call) => call.name == 'playNote'),
      hasLength(playCount),
    );
    expect(c.engine, isNull);
    await remove(tester);
  });

  testWidgets('held sound ends at the bar tail; pause and exit clear voices', (
    tester,
  ) async {
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: MemoryPreferences());
    addTearDown(c.dispose);
    mocks(tester, const Size(800, 360), 'zh-Hans', 1, c);
    c.repository.profile['settings_json'] = jsonEncode({
      'sound_enabled': true,
      'gain_permille': 600,
    });
    final calls = <({String name, int time})>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            calls.add((name: call.method, time: clock.now));
            return {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': call.method == 'playNote'
                  ? {'voice_id': 1}
                  : {'prepared': true, 'accepted': true},
            };
          },
        );
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPerformancePage(
          c: c,
          piece: c.content.pieces.first,
          tempo: 60,
        ),
      ),
    );
    await frames(tester);
    clock.now = 16000000; // Four-beat lead in plus first twelve quarter notes.
    await tester.pump(const Duration(milliseconds: 16));
    final p = tester.widget<ScrollingScore>(find.byType(ScrollingScore)).player;
    expect(p.currentIndex, 12);
    expect(calls.where((call) => call.name == 'syncPieceBacking'), isNotEmpty);
    final rect = tester.getRect(find.byType(PianoKeyboard));
    final gesture = await tester.startGesture(
      rect.center,
    ); // Key 3, dotted quarter.
    await tester.pump();
    expect(p.targetPressed, isTrue);
    clock.now = 17500000;
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();
    expect(p.currentIndex, 13);
    expect(p.targetPressed, isFalse);
    expect(calls.where((call) => call.name == 'stopVoice').last.time, 17500000);
    await gesture.up();
    c.previewInterruptions.value++;
    await tester.pumpAndSettle();
    expect(p.mode, ScrollPieceMode.paused);
    expect(calls.where((call) => call.name == 'stopPieceBacking'), isNotEmpty);
    final frozen = p.elapsedUs;
    clock.now += 10000000;
    await tester.pump(const Duration(seconds: 10));
    expect(p.elapsedUs, frozen);
    expect(c.engine, isNull);
    await remove(tester);
    expect(
      calls.last.name,
      anyOf('allNotesOff', 'stopSpeech', 'setTrainingFullscreen'),
    );
  });
}
