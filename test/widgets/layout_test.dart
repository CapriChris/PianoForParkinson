import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';

import '../domain/task_engine_test.dart' show create, ready, play;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(360, 640), const Size(800, 1280)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'home, settings and details ${size.width} $locale text $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('piano_training/platform/v1'),
                  (call) async => {
                    'ok': true,
                    'request_id': (call.arguments as Map)['request_id'],
                    'data': <String, dynamic>{},
                  },
                );
            final c = AppController();
            c.initialized = true;
            c.audioReady = true;
            c.repository.profile = {
              'locale': locale,
              'mode': 'ASSIST',
              'onboarding_completed': 1,
              'settings_json': jsonEncode({
                'high_contrast': false,
                'sound_enabled': true,
                'gain_permille': 600,
              }),
            };
            await tester.pumpWidget(PianoApp(controller: c));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.byIcon(Icons.settings_outlined));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final clock = ManualClock(), engine = create(ManualClock());
            final eClock = engine.clock as ManualClock;
            ready(engine, eClock);
            play(engine, eClock, List<int>.from(engine.expected));
            engine.finish('EXITED');
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResultPage(
                      c: c,
                      record: {
                        'task_id': engine.taskId,
                        'status': 'EXITED',
                        'parameter_profile_version': 'demo-cognitive-1.0.0',
                        'metric_version': 'metrics-1.0.0',
                        'mode': 'ASSIST',
                        'result_json': canonical(engine.summary()),
                      },
                    ),
                  ),
                );
            await tester.pumpAndSettle();
            final title = find.text(
              locale == 'zh-Hans' ? '详细训练表现' : 'Practice details',
            );
            await tester.scrollUntilVisible(
              title,
              180,
              scrollable: find
                  .descendant(
                    of: find.byType(ResultPage),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await Scrollable.ensureVisible(
              tester.element(title),
              alignment: 0.1,
            );
            await tester.pumpAndSettle();
            await tester.tap(title);
            await tester.pumpAndSettle();
            expect(find.byType(MetricRate), findsWidgets);
            for (final timing
                in find.byType(MetricTiming).evaluate().toList()) {
              await tester.ensureVisible(find.byWidget(timing.widget));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            expect(clock.now, 0);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
            await tester.pump();
          },
        );
      }
    }
  }
}
