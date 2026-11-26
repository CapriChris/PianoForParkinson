import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/waterfall_score.dart';
import 'package:piano_practice/features/piece_sheet_preview.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import '../domain/scrolling_piece_test.dart' show score;
import 'cognitive_pages_test.dart' show mocks;

PianoPiece sixKeys() {
  final data = {
    ...score().data,
    'key_steps': [0, 1, 2, 3, 4, 5],
  }..remove('content_hash');
  return PianoPiece.fromJson({...data, 'content_hash': digest(data)});
}

void main() {
  testWidgets(
    'translucent cue crosses the pressed key recess without a doubled rectangle',
    (tester) async {
      final imageKey = GlobalKey();
      final piece = sixKeys();
      final p =
          ScrollingPiecePlayer(piece, ManualClock(), tempo: 60, training: true)
            ..mode = ScrollPieceMode.running
            ..elapsedUs = 500000;
      final frames = ValueNotifier(0);
      final key = piece.notes.first.key;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: imageKey,
                child: SizedBox(
                  width: 360,
                  height: 176,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 76,
                        child: WaterfallKeyBases(
                          count: piece.keyCount,
                          player: p,
                          frames: frames,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 138,
                        child: WaterfallScore(
                          player: p,
                          frames: frames,
                          keyOverlap: 38,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 76,
                        child: PianoKeyboard(
                          count: piece.keyCount,
                          active: const {},
                          locked: true,
                          splitZones: false,
                          externalKeyBases: true,
                          demonstratingKeys: {key},
                          feedbackParticles: false,
                          onDown: (_, _, _, _) {},
                          onUp: (_, _, _, _) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary =
          imageKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final width = (360 - 40) / 6;
        for (final x in [
          (key * (width + 8)).ceil() + 2,
          (key * (width + 8) + width / 2).round(),
        ]) {
          for (var channel = 0; channel < 3; channel++) {
            final above = pixels.getUint8((99 * 360 + x) * 4 + channel);
            final below = pixels.getUint8((101 * 360 + x) * 4 + channel);
            expect((above - below).abs(), lessThanOrEqualTo(10));
          }
        }
        image.dispose();
      });
      p.elapsedUs = -1000000;
      frames.value++;
      await tester.pump();
      final palette = imageKey.currentContext!.qin;
      final recess = Color.lerp(palette.disabled, palette.edge, .42)!;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = (key * ((360 - 40) / 6 + 8) + (360 - 40) / 12).round();
        final offset = (101 * 360 + x) * 4;
        final actual =
            (pixels.getUint8(offset) << 16) |
            (pixels.getUint8(offset + 1) << 8) |
            pixels.getUint8(offset + 2);
        expect(
          actual,
          recess.toARGB32() & 0xffffff,
          reason: 'A direct press before cue contact retains the upper recess',
        );
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      frames.dispose();
    },
  );
  testWidgets(
    'six preview keys have equal gaps and share the cue canvas width',
    (tester) async {
      final c = AppController();
      mocks(tester, const Size(400, 800), 'zh-Hans', 1, c);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            body: PieceSheetPreview(
              c: c,
              piece: sixKeys(),
              tempo: 60,
              waterfall: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final canvas = tester.getRect(
        find.byKey(const ValueKey('waterfall-score')),
      );
      final keys = [
        for (var i = 0; i < 6; i++)
          tester.getRect(find.byKey(ValueKey('key-feedback-$i'))),
      ];
      expect(keys.first.left, closeTo(canvas.left, .01));
      expect(keys.last.right, closeTo(canvas.right, .01));
      for (var i = 1; i < 6; i++) {
        expect(keys[i].width, closeTo(keys.first.width, .01));
        expect(keys[i].left - keys[i - 1].right, closeTo(8, .01));
      }
      expect(canvas.bottom, closeTo(keys.first.center.dy, .01));
      expect(
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).locked,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test('cues approach during lead-in, hide during count-in and cover the full key width', () async {
    final p = ScrollingPiecePlayer(
      sixKeys(),
      ManualClock(),
      tempo: 60,
      training: true,
    );
    final frames = ValueNotifier(0);
    Future<List<int>> row(int y, {bool visible = true}) async {
      final recorder = ui.PictureRecorder();
      WaterfallPainter(
        p,
        frames,
        edge: Colors.black,
        reducedMotion: true,
        keyOverlap: 38,
        showCues: visible,
      ).paint(Canvas(recorder), const Size(360, 138));
      final picture = recorder.endRecording();
      final image = await picture.toImage(360, 138);
      final bytes = (await image.toByteData())!;
      final xs = [
        for (var x = 0; x < 360; x++)
          if (bytes.getUint8((y * 360 + x) * 4 + 3) > 0) x,
      ];
      image.dispose();
      picture.dispose();
      return xs;
    }

    expect(await row(95), isEmpty);
    p.mode = ScrollPieceMode.running;
    p.elapsedUs = -1000000;
    expect(await row(20), isNotEmpty);
    expect(await row(95), isEmpty);
    expect(await row(20, visible: false), isEmpty);
    p.elapsedUs = -100000;
    expect(await row(80), isNotEmpty);
    expect(await row(99), isEmpty);
    p.elapsedUs = 0;
    expect(await row(95), isNotEmpty);
    p.elapsedUs = 500000;
    expect(await row(95, visible: false), isEmpty);
    final xs = await row(110);
    final key = p.piece.notes.first.key;
    final width = (360 - 5 * 8) / 6;
    expect(xs.first, closeTo(key * (width + 8), 1));
    expect(xs.last + 1, closeTo(key * (width + 8) + width, 1));
    frames.dispose();
  });
}
