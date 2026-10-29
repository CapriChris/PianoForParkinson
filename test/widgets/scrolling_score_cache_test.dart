import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/features/piece_audition_preview.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/piece_playback_keys.dart';
import 'package:piano_practice/ui/qin_theme.dart';
import 'package:piano_practice/ui/text_scale.dart';

void main() {
  testWidgets('supplied white-key preview fits seven keys at large text', (
    tester,
  ) async {
    final piece = PianoPiece.fromJson(
      jsonDecode(
        File('assets/content/piece-you-are-my-sunshine-001.json')
            .readAsStringSync(),
      ) as Json,
    );
    final player = ScrollingPiecePlayer(piece, ManualClock(), tempo: 40)
      ..start();
    final frames = ValueNotifier<int>(0);
    addTearDown(frames.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Center(
            child: SizedBox(
              width: 328,
              child: PieceAuditionPreview(
                player: player,
                frames: frames,
                chinese: true,
              ),
            ),
          ),
        ),
      ),
    );
    final cache = ScrollingScoreCache()
      ..prepare(const Size(304, 156), piece, QinPalette.standard);
    for (final rect in cache.rectangles) {
      expect(rect.top, greaterThanOrEqualTo(12));
      expect(rect.bottom, lessThanOrEqualTo(144));
    }
    cache.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('moving frames and note-boundary rebuilds reuse score layout', (
    tester,
  ) async {
    final piece = PianoPiece.fromJson(
      jsonDecode(
        File('test/fixtures/legacy-pieces/piece-you-are-my-sunshine-001.json')
            .readAsStringSync(),
      ) as Json,
    );
    final clock = ManualClock();
    final player = ScrollingPiecePlayer(piece, clock, tempo: 80)
      ..start(leadBeats: 0);
    final frames = ValueNotifier<int>(0);
    addTearDown(frames.dispose);
    Widget page(bool demo) => MaterialApp(
      theme: qinTheme(highContrast: false),
      home: Center(
        child: SizedBox(
          width: 720,
          height: 180,
          child: ScrollingScore(
            player: player,
            frames: frames,
            chinese: true,
            demonstrating: demo,
          ),
        ),
      ),
    );
    ScrollingScoreCache current() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('scrolling-score')),
                    )
                    .painter!
                as ScrollingScorePainter)
            .cache;
    await tester.pumpWidget(page(false));
    final cache = current();
    final staff = cache.staff, cursor = cache.cursor;
    final layouts = cache.paragraphLayouts;
    expect(cache.layoutBuilds, 1);
    expect(layouts, greaterThan(0));
    for (var i = 0; i < 180; i++) {
      clock.now += 16667;
      player.tick();
      if (i % 30 == 0) await tester.pumpWidget(page(i.isEven));
      frames.value++;
      await tester.pump(const Duration(microseconds: 16667));
    }
    expect(identical(cache, current()), isTrue);
    expect(cache.layoutBuilds, 1);
    expect(cache.paragraphLayouts, layouts);
    expect(identical(cache.staff, staff), isTrue);
    expect(identical(cache.cursor, cursor), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(cache.staff, isNull);
    expect(cache.cursor, isNull);
  });

  testWidgets('score and piano keys ignore app text size', (tester) async {
    final piece = PianoPiece.fromJson(
      jsonDecode(
        File('assets/content/piece-you-are-my-sunshine-001.json')
            .readAsStringSync(),
      ) as Json,
    );
    final player = ScrollingPiecePlayer(piece, ManualClock(), tempo: 40);
    final frames = ValueNotifier<int>(0);
    addTearDown(frames.dispose);
    Widget page(int percent) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: AppTextScaler(const TextScaler.linear(1), percent),
        ),
        child: Center(
          child: SizedBox(
            width: 328,
            child: PieceAuditionPreview(
              player: player,
              frames: frames,
              chinese: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(page(80));
    final cache =
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('scrolling-score')),
                    )
                    .painter!
                as ScrollingScorePainter)
            .cache;
    final builds = cache.layoutBuilds;
    final width = cache.label('3', Colors.black).text.width;
    final key = find.byKey(const ValueKey('preview-key-0'));
    final keySize = tester.getSize(key);
    await tester.pumpWidget(page(120));
    expect(cache.layoutBuilds, builds);
    expect(cache.label('3', Colors.black).text.width, width);
    expect(tester.getSize(key), keySize);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'training and review keyboard text remains fixed as app text changes',
    (tester) async {
      final piece = PianoPiece.fromJson(
        jsonDecode(
          File('assets/content/piece-you-are-my-sunshine-001.json')
              .readAsStringSync(),
        ) as Json,
      );
      Widget page(int percent) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: AppTextScaler(const TextScaler.linear(1.25), percent),
          ),
          child: Center(
            child: SizedBox(
              width: 328,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 120,
                    child: PianoKeyboard(
                      count: 3,
                      active: const {0, 1, 2},
                      showKeyMarks: false,
                      onDown: (_, _, _, _) {},
                      onUp: (_, _, _, _) {},
                    ),
                  ),
                  PiecePlaybackKeys(piece: piece, active: const {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(80));
      final training = find.descendant(
        of: find.byType(PianoKeyboard),
        matching: find.text('1'),
      );
      final labelSize = tester.getSize(training);
      final keySize = tester.getSize(
        find.byKey(const ValueKey('key-feedback-0')),
      );
      final reviewSize = tester.getSize(
        find.byKey(const ValueKey('playback-feedback-0')),
      );
      await tester.pumpWidget(page(120));
      expect(tester.getSize(training), labelSize);
      expect(
        tester.getSize(find.byKey(const ValueKey('key-feedback-0'))),
        keySize,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('playback-feedback-0'))),
        reviewSize,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('resize and contrast changes refresh cached score resources', (
    tester,
  ) async {
    final piece = PianoPiece.fromJson(
      jsonDecode(
        File('test/fixtures/legacy-pieces/piece-happy-birthday-001.json')
            .readAsStringSync(),
      ) as Json,
    );
    final player = ScrollingPiecePlayer(piece, ManualClock(), tempo: 60);
    final frames = ValueNotifier<int>(0);
    addTearDown(frames.dispose);
    Widget page(double width, bool contrast) => MaterialApp(
      theme: qinTheme(highContrast: contrast),
      home: Center(
        child: SizedBox(
          width: width,
          height: 156,
          child: ScrollingScore(player: player, frames: frames, chinese: true),
        ),
      ),
    );
    await tester.pumpWidget(page(600, false));
    final cache =
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('scrolling-score')),
                    )
                    .painter!
                as ScrollingScorePainter)
            .cache;
    final original = cache.staff;
    await tester.pumpWidget(page(340, false));
    expect(cache.layoutBuilds, 2);
    expect(identical(cache.staff, original), isFalse);
    final resized = cache.staff;
    await tester.pumpWidget(page(340, true));
    await tester.pumpAndSettle();
    expect(cache.layoutBuilds, 3);
    expect(identical(cache.staff, resized), isFalse);
    expect(cache.labels, contains('5\u0323'));
    expect(tester.takeException(), isNull);
  });
}
