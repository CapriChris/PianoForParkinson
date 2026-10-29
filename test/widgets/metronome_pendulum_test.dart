import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/features/lesson_beat_timeline.dart';
import 'package:piano_practice/features/metronome_pendulum.dart';
import 'package:piano_practice/ui/qin_theme.dart';

void main() {
  for (final size in [const Size(24, 24), const Size(36, 32)]) {
    test('rigid arm and attached weight throughout swing at $size', () {
      Offset? pivot;
      double? length, weightDistance;
      for (var step = 0; step <= 100; step++) {
        final arm = MetronomePendulum(
          -1 + step / 50,
          Colors.green,
        ).geometry(size);
        final rod = arm.tip - arm.pivot;
        final weight = arm.weight - arm.pivot;
        pivot ??= arm.pivot;
        length ??= rod.distance;
        weightDistance ??= weight.distance;
        expect(arm.pivot, pivot);
        expect(rod.distance, closeTo(length, 1e-9));
        expect(weight.distance, closeTo(weightDistance, 1e-9));
        // Collinearity plus dot product: the weight stays on the rod segment.
        expect(rod.dx * weight.dy - rod.dy * weight.dx, closeTo(0, 1e-9));
        expect(rod.dx * weight.dx + rod.dy * weight.dy, greaterThan(0));
        expect(weight.distance, lessThan(rod.distance));
        expect((Offset.zero & size).contains(arm.tip), isTrue);
        final radius = (size.shortestSide / 10).clamp(2.5, 3.0);
        expect(arm.weight.dx - radius, greaterThanOrEqualTo(0));
        expect(arm.weight.dx + radius, lessThanOrEqualTo(size.width));
        expect(arm.weight.dy - radius, greaterThanOrEqualTo(0));
        expect(arm.weight.dy + radius, lessThanOrEqualTo(size.height));
      }
    });
  }

  test('repaint follows position and theme changes', () {
    const original = MetronomePendulum(0, Colors.green);
    expect(original.shouldRepaint(original), isFalse);
    expect(
      const MetronomePendulum(.5, Colors.green).shouldRepaint(original),
      isTrue,
    );
    expect(
      const MetronomePendulum(0, Colors.white).shouldRepaint(original),
      isTrue,
    );
  });

  testWidgets(
    'lesson needle, selected beat and progress share the demo clock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> show(int ms, {bool running = true, bool reduced = false}) =>
          tester.pumpWidget(
            MaterialApp(
              theme: qinTheme(highContrast: false),
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: Scaffold(
                  body: LessonBeatTimeline(
                    page: 0,
                    elapsedMs: ms,
                    running: running,
                    chinese: true,
                    compact: true,
                  ),
                ),
              ),
            ),
          );
      MetronomePendulum needle() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<MetronomePendulum>()
          .single;

      for (var beat = 0; beat < 4; beat++) {
        final ms = beat * 1500 + 750;
        await show(ms);
        expect(needle().position, closeTo(beat.isEven ? 1 : -1, 1e-9));
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          closeTo(ms / 6000, 1e-9),
        );
        final beats = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .where(
              (w) => RegExp(r'^[1-4] 拍点$').hasMatch(w.properties.label ?? ''),
            );
        expect(beats.length, 4);
        expect(
          beats
              .where((w) => w.properties.selected == true)
              .single
              .properties
              .label,
          '${beat + 1} 拍点',
        );
        await show((beat + 1) * 1500 - 1);
        final before = needle().position;
        await show((beat + 1) * 1500);
        expect((needle().position - before).abs(), lessThan(.003));
      }
      await show(750, reduced: true);
      expect(needle().position, 0);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(750 / 6000, 1e-9),
      );
      await show(6000, running: false);
      expect(needle().position, 0);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
      await show(0, running: false);
      expect(needle().position, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
