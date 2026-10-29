import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/features/trend_page.dart';

import '../domain/history_test.dart' show sealedRow;

void main() {
  for (final width in [360.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final count in [2, 3]) {
        testWidgets('trend $count points width $width scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final chart = TrendChart(
            points: List.generate(
              count,
              (i) => TrendPoint.fromRow(sealedRow(numerator: i)),
            ),
            selected: count - 1,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 640),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: chart,
                  ),
                ),
              ),
            ),
          );
          expect(chart.connectsPoints, count >= 3);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
