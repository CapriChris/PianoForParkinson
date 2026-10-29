import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/ui/note_label.dart';

void main() {
  testWidgets(
    'high octave dots are centered above the degree and remain visible',
    (tester) async {
      await tester.runAsync(() async {
        for (final size in [18.0, 36.0]) {
          for (final value in ['1\u0307', '♯4\u0307', '6\u0307\u0307']) {
            final layout = ScoreNoteLabel(
              value,
              TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            );
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawColor(Colors.white, BlendMode.src);
            layout.paint(canvas, const Offset(5, 5));
            final picture = recorder.endRecording();
            final image = await picture.toImage(120, 100);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final digit = RegExp(r'[1-7]').firstMatch(layout.text.plainText)!;
            final box = layout.text
                .getBoxesForSelection(
                  TextSelection(
                    baseOffset: digit.start,
                    extentOffset: digit.end,
                  ),
                )
                .single;
            var xTotal = 0.0, pixels = 0;
            for (var y = 5; y < (5 + layout.highSpace).floor(); y++) {
              for (
                var x = (5 + box.left).floor();
                x < (5 + box.right).ceil();
                x++
              ) {
                final at = (y * 120 + x) * 4;
                if (bytes[at] < 200 &&
                    bytes[at + 1] < 200 &&
                    bytes[at + 2] < 200) {
                  xTotal += x + .5;
                  pixels++;
                }
              }
            }
            expect(
              pixels,
              greaterThan(0),
              reason: 'High octave dots must be visible above the digit.',
            );
            expect(xTotal / pixels, closeTo(5 + (box.left + box.right) / 2, 1));
            image.dispose();
            picture.dispose();
            layout.dispose();
          }
        }
      });
    },
  );
}
