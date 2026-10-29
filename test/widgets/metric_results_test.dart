import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/ui/metric_visuals.dart';

import 'cognitive_pages_test.dart' show mocks;

void main() {
  for (final task in [
    'S1_GUIDED',
    'S2_RHYTHM',
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'M1_ALTERNATE',
    'M2_DUAL_ZONE',
  ]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final empty in [true, false]) {
        testWidgets(
          'sealed result dashboard $task $locale empty=$empty at large text',
          (tester) async {
            final summary = PracticeMetrics.build(
              taskId: task,
              version: 'metrics-2.1.0',
              attempts: [],
              trials: [],
              events: [],
              planned: 10,
              complete: false,
            );
            if (!empty) {
              summary['completed'] = 10;
              summary['active_duration_us'] = 35000000;
              for (final entry in (summary['rates'] as Json).entries) {
                entry.value['numerator'] = 7;
                entry.value['denominator'] = 10;
              }
              for (final entry in (summary['timing_groups'] as Json).entries) {
                summary['timing_groups'][entry.key] = timingStatistics(
                  List.generate(10, (i) => 300000 + i * 10000),
                );
              }
            }
            final before = canonical(summary);
            final c = AppController();
            mocks(tester, const Size(360, 720), locale, 2, c);
            await tester.pumpWidget(PianoApp(controller: c));
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResultPage(
                      c: c,
                      record: {
                        'task_id': task,
                        'status': 'EXITED',
                        'mode': 'ASSIST',
                        'parameter_profile_version': 'demo',
                        'metric_version': 'metrics-2.1.0',
                        'result_json': before,
                      },
                    ),
                  ),
                );
            await tester.pumpAndSettle();
            final scroll = find
                .descendant(
                  of: find.byType(ResultPage),
                  matching: find.byType(Scrollable),
                )
                .first;
            await tester.scrollUntilVisible(
              find.byType(MetricRateGraphic),
              120,
              scrollable: scroll,
            );
            expect(find.byType(MetricRateGraphic), findsOneWidget);
            final detail = find.text(
              locale == 'en' ? 'Practice details' : '详细训练表现',
            );
            await tester.scrollUntilVisible(detail, 140, scrollable: scroll);
            await Scrollable.ensureVisible(
              tester.element(detail),
              alignment: .1,
            );
            await tester.pumpAndSettle();
            await tester.tap(detail);
            await tester.pumpAndSettle();
            for (final element
                in find.byType(MetricTiming).evaluate().toList()) {
              await tester.ensureVisible(find.byWidget(element.widget));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            final finalTile = find.text(
              locale == 'en' ? 'Record information' : '记录信息',
            );
            await tester.ensureVisible(finalTile);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              canonical(summary),
              before,
              reason: 'Display must not mutate sealed values',
            );
            await tester.pumpWidget(const SizedBox());
            c.dispose();
            await tester.pump();
          },
        );
      }
    }
  }
}
