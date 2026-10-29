import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/domain/trend_metrics.dart';
import 'package:piano_practice/features/trend_page.dart';
import 'package:piano_practice/ui/metric_visuals.dart';
import 'package:piano_practice/ui/qin_theme.dart';

Widget page(Widget body, {double scale = 1, bool contrast = false}) =>
    MaterialApp(
      theme: qinTheme(highContrast: contrast),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: body),
          ),
        ),
      ),
    );
void main() {
  testWidgets(
    'unknown rate is distinct from measured zero, including semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        page(
          const Column(
            children: [
              MetricRateGraphic(label: 'Unknown', numerator: 0, denominator: 0),
              MetricRateGraphic(
                label: 'Measured',
                numerator: 0,
                denominator: 10,
              ),
            ],
          ),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.bySemanticsLabel('Unknown，—，暂无有效样本'), findsOneWidget);
      expect(find.bySemanticsLabel('Measured，0.0%，0 / 10'), findsOneWidget);
      semantics.dispose();
    },
  );
  for (final width in [320.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final chinese in [true, false]) {
        for (final contrast in [true, false]) {
          testWidgets(
            'visual metrics fit $width $scale $chinese contrast=$contrast',
            (tester) async {
              tester.view.physicalSize = Size(width, 800);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(
                page(
                  Column(
                    children: [
                      MetricRateGraphic(
                        label: chinese ? '完整正确序列' : 'Fully correct sequences',
                        numerator: 7,
                        denominator: 10,
                        hero: true,
                        chinese: chinese,
                      ),
                      MetricTimingGraphic(
                        label: chinese
                            ? '无帮助连续命中间隔'
                            : 'Consecutive hit interval without assistance',
                        stats: timingStatistics(
                          List.generate(10, (i) => i * 500000),
                        ),
                        chinese: chinese,
                        showCv: true,
                      ),
                      MetricCountBars(
                        title: 'Input events',
                        counts: const {'Short presses': 0, 'Out of window': 2},
                      ),
                      MetricNoteMap(
                        total: 512,
                        matched: const {0, 1, 3, 511},
                        chinese: chinese,
                      ),
                    ],
                  ),
                  scale: scale,
                  contrast: contrast,
                ),
              );
              final bars = tester.widgetList<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              );
              expect(
                bars.every(
                  (b) => b.value != null && b.value! >= 0 && b.value! <= 1,
                ),
                isTrue,
              );
              expect(
                tester
                    .getSize(find.byKey(const ValueKey('note-match-map')))
                    .width,
                greaterThan(200),
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
  testWidgets(
    'CV above 100 percent stays numeric and is not turned into accuracy',
    (tester) async {
      final stats = timingStatistics([1, 1, 1, 1, 1, 1, 1, 1, 1, 1000000]);
      await tester.pumpWidget(
        page(
          MetricTimingGraphic(
            label: 'Interval',
            stats: stats,
            showCv: true,
            chinese: false,
          ),
        ),
      );
      expect(find.textContaining('CV 316.2%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'chart taps select the exact block including a missing-value slot',
    (tester) async {
      final points = List.generate(
        3,
        (i) => TrendPoint.fromRow({
          'block_id': '$i',
          'ended_utc_ms': i * 1000,
          'session_utc_offset_minutes': 480,
          'comparison_key': 'condition',
          'metric_version': 'metrics',
          'result_json': canonical({
            'version': 'metrics',
            'comparison_key': 'condition',
            'rates': {
              'primary': {'numerator': i, 'denominator': 3},
              if (i != 1)
                'unassisted_primary': {'numerator': i, 'denominator': 3},
            },
          }),
        }),
      );
      var selected = -1;
      await tester.pumpWidget(
        page(
          TrendChart(
            points: points,
            selected: 0,
            metric: const TrendMetric(
              id: 'unassisted',
              zh: '无帮助',
              en: 'Unassisted',
              source: 'unassisted_primary',
            ),
            onSelected: (i) => selected = i,
          ),
        ),
      );
      final chart = tester.widget<TrendChart>(find.byType(TrendChart));
      expect(chart.values, [0.0, null, 200 / 3]);
      expect(chart.connectsPoints, isFalse);
      final gesture = find.descendant(
        of: find.byType(TrendChart),
        matching: find.byType(GestureDetector),
      );
      final rect = tester.getRect(gesture);
      await tester.tapAt(rect.center);
      expect(selected, 1);
      await tester.tapAt(Offset(rect.right - 9, rect.center.dy));
      expect(selected, 2);
    },
  );
}
