import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/cognitive_cue.dart';
import 'package:piano_practice/features/key_mark.dart';
import 'package:piano_practice/features/key_press_feedback.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/piece_audition_preview.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/ui/note_colors.dart';
import 'package:piano_practice/ui/qin_theme.dart';

Widget page(Widget child, {bool reducedMotion = false}) => MaterialApp(
  theme: qinTheme(highContrast: false),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reducedMotion),
    child: Scaffold(
      body: Center(child: SizedBox(width: 480, height: 144, child: child)),
    ),
  ),
);

Color? keyColor(WidgetTester tester, int i) =>
    ((tester
                        .widget<KeyPressFeedback>(
                          find.byKey(ValueKey('key-feedback-$i')),
                        )
                        .child
                    as Container)
                .decoration
            as BoxDecoration)
        .color;

KeyParticlesPainter particles(WidgetTester tester, String key) =>
    tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byType(CustomPaint),
                  )
                  .last,
            )
            .painter!
        as KeyParticlesPainter;

Future<void> movingFrame(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  test(
    'seven vivid tones follow degrees across registers with readable labels',
    () {
      expect(NoteColors.tones.map((t) => t.fill).toSet(), hasLength(7));
      for (var i = 0; i < 7; i++) {
        final tone = NoteColors.degree(i);
        expect(NoteColors.degree(i - 7), same(tone));
        expect(NoteColors.degree(i + 7), same(tone));
        for (final fill in [tone.fill, tone.pressed]) {
          final contrast =
              (fill.computeLuminance() + .05) /
              (tone.ink.computeLuminance() + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );

  test('particles stay outside every edge of the key face', () {
    for (final size in [const Size(86, 120), const Size(220, 320)]) {
      for (final t in [.001, .2, .6, .99]) {
        for (final pressed in [0.0, 1.0]) {
          final painter = KeyParticlesPainter(
            AlwaysStoppedAnimation(t),
            NoteColors.degree(0).fill,
            AlwaysStoppedAnimation(pressed),
          );
          final face = painter.faceRect(size);
          for (var i = 0; i < 12; i++) {
            // Include the maximum particle radius, not just its center.
            expect(
              face.inflate(3.2).contains(painter.particleCenter(size, i)),
              isFalse,
            );
          }
        }
      }
    }
  });

  testWidgets('key face sinks and rebounds without changing its input bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        PianoKeyboard(
          count: 3,
          active: const {0, 1, 2},
          onDown: (p, k, d, xy) {},
          onUp: (p, k, c, xy) {},
        ),
      ),
    );
    final key = find.byKey(const ValueKey('key-feedback-0'));
    final transform = find.descendant(
      of: key,
      matching: find.byKey(const ValueKey('key-face-translation')),
    );
    double depth() => tester.widget<Transform>(transform).transform.storage[13];
    final bounds = tester.getRect(key);
    expect(depth(), 0);
    final finger = await tester.startGesture(tester.getCenter(key));
    await movingFrame(tester);
    expect(depth(), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(depth(), closeTo(5, .01));
    expect(tester.getRect(key), bounds);
    await finger.up();
    await tester.pumpAndSettle();
    expect(depth(), 0);
    expect(tester.getRect(key), bounds);
  });

  testWidgets(
    'octave keys stay uniform at rest, match on press, and keep all pointer events',
    (tester) async {
      final downs = <int>[], ups = <int>[];
      await tester.pumpWidget(
        page(
          PianoKeyboard(
            count: 3,
            active: const {0, 1, 2},
            noteDegrees: const [0, 7, -7],
            labels: const ['1\u0323', '1', '1\u0307'],
            showKeyMarks: false,
            onDown: (p, k, d, xy) => downs.add(p),
            onUp: (p, k, c, xy) => ups.add(p),
          ),
        ),
      );
      expect([
        for (var i = 0; i < 3; i++) keyColor(tester, i),
      ], everyElement(QinPalette.standard.surface));
      final gestures = <TestGesture>[];
      for (var i = 0; i < 3; i++) {
        gestures.add(
          await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey('key-feedback-$i'))),
            pointer: i + 1,
          ),
        );
      }
      await movingFrame(tester);
      expect([
        for (var i = 0; i < 3; i++) keyColor(tester, i),
      ], everyElement(NoteColors.degree(0).pressed));
      for (var i = 0; i < 3; i++) {
        expect(
          particles(tester, 'key-feedback-$i').animation.value,
          greaterThan(0),
        );
      }
      expect(find.byType(KeyMark), findsNothing);
      expect(find.byType(ShapeMark), findsNothing);
      for (final gesture in gestures) {
        await gesture.up();
      }
      await tester.pumpAndSettle();
      expect(downs, [1, 2, 3]);
      expect(ups, [1, 2, 3]);
      expect([
        for (var i = 0; i < 3; i++) keyColor(tester, i),
      ], everyElement(QinPalette.standard.surface));
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('non-piece training retains rule shapes and has press feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        PianoKeyboard(
          count: 3,
          active: const {0, 1, 2},
          showShapes: true,
          onDown: (p, k, d, xy) {},
          onUp: (p, k, c, xy) {},
        ),
      ),
    );
    expect(find.byType(ShapeMark), findsNWidgets(3));
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('key-feedback-1'))),
    );
    await movingFrame(tester);
    expect(particles(tester, 'key-feedback-1').animation.value, greaterThan(0));
    expect(
      particles(tester, 'key-feedback-1').color,
      QinPalette.standard.primary,
    );
    expect(keyColor(tester, 1), QinPalette.standard.primary);
    await finger.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'disabled keys and locked cues emit no particles; reduced motion keeps static feedback',
    (tester) async {
      PianoKeyboard keyboard({bool locked = false}) => PianoKeyboard(
        count: 3,
        active: const {0},
        locked: locked,
        highlighted: 0,
        highlightWhileLocked: true,
        onDown: (p, k, d, xy) {},
        onUp: (p, k, c, xy) {},
      );
      await tester.pumpWidget(page(keyboard()));
      await tester.tap(find.byKey(const ValueKey('key-feedback-1')));
      await movingFrame(tester);
      expect(particles(tester, 'key-feedback-1').animation.value, 0);
      await tester.pumpWidget(page(keyboard(locked: true)));
      await movingFrame(tester);
      expect(particles(tester, 'key-feedback-0').animation.value, 0);
      await tester.pumpWidget(page(keyboard(), reducedMotion: true));
      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('key-feedback-0'))),
      );
      await movingFrame(tester);
      expect(keyColor(tester, 0), QinPalette.standard.primary);
      expect(particles(tester, 'key-feedback-0').animation.value, 0);
      await finger.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'repeated same-key demo notes replay one bounded burst and interruption clears it',
    (tester) async {
      final interrupted = ValueNotifier<int>(0);
      addTearDown(interrupted.dispose);
      Widget demo(int step, {bool running = true}) => page(
        PianoKeyboard(
          count: 3,
          active: const {0, 1, 2},
          locked: true,
          highlighted: 0,
          highlightWhileLocked: true,
          interruptions: interrupted,
          demonstratingKeys: running ? const {0} : const {},
          demonstrationPulse: step,
          onDown: (p, k, d, xy) {},
          onUp: (p, k, c, xy) {},
        ),
      );
      await tester.pumpWidget(demo(1));
      await movingFrame(tester);
      await tester.pump(const Duration(milliseconds: 250));
      final progress = particles(tester, 'key-feedback-0').animation.value;
      await tester.pumpWidget(demo(2));
      await movingFrame(tester);
      expect(
        particles(tester, 'key-feedback-0').animation.value,
        lessThan(progress),
      );
      interrupted.value++;
      await tester.pump();
      expect(particles(tester, 'key-feedback-0').animation.value, 0);
      await tester.pumpWidget(demo(2, running: false));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'ending a demo does not replay an older manual press as a response cue',
    (tester) async {
      Widget keyboard(bool demo) => page(
        PianoKeyboard(
          count: 3,
          active: const {0, 1, 2},
          locked: demo,
          demonstratingKeys: demo ? const {0} : const {},
          demonstrationPulse: 1,
          onDown: (p, k, d, xy) {},
          onUp: (p, k, c, xy) {},
        ),
      );
      await tester.pumpWidget(keyboard(false));
      await tester.tap(find.byKey(const ValueKey('key-feedback-0')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(keyboard(true));
      await movingFrame(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(keyboard(false));
      await movingFrame(tester);
      expect(
        particles(tester, 'key-feedback-0').animation.status,
        AnimationStatus.completed,
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'piece preview uses matching note/key colors, no marks, and animates repeated notes',
    (tester) async {
      final piece = PianoPiece.fromJson(
        jsonDecode(
          File('assets/content/piece-ode-to-joy-001.json').readAsStringSync(),
        ) as Json,
      );
      final clock = ManualClock();
      final player = ScrollingPiecePlayer(piece, clock, tempo: 60)
        ..start(leadBeats: 0);
      final frames = ValueNotifier<int>(0);
      addTearDown(frames.dispose);
      Widget preview() => MaterialApp(
        theme: qinTheme(highContrast: false),
        home: Scaffold(
          body: PieceAuditionPreview(
            player: player,
            frames: frames,
            chinese: true,
          ),
        ),
      );
      await tester.pumpWidget(preview());
      await movingFrame(tester);
      final pressed = tester.widget<Container>(
        find.byKey(const ValueKey('preview-key-2')),
      );
      expect(
        (pressed.decoration as BoxDecoration).color,
        NoteColors.degree(2).pressed,
      );
      expect(find.byType(KeyMark), findsNothing);
      expect(find.byType(ShapeMark), findsNothing);
      final cache =
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('scrolling-score')),
                      )
                      .painter!
                  as ScrollingScorePainter)
              .cache;
      expect(cache.fills.first, NoteColors.degree(2).fill);
      final layouts = cache.paragraphLayouts;
      await tester.pump(const Duration(milliseconds: 250));
      final before = particles(tester, 'preview-feedback-2').animation.value;
      clock.now = 1000000;
      player.tick();
      await tester.pumpWidget(preview());
      await movingFrame(tester);
      expect(player.currentIndex, 1);
      expect(
        particles(tester, 'preview-feedback-2').animation.value,
        lessThan(before),
      );
      expect(cache.paragraphLayouts, layouts);
      player.pause();
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();
      expect(particles(tester, 'preview-feedback-2').animation.value, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
