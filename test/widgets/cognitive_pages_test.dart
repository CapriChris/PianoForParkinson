import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/cognitive_cue.dart';
import 'package:piano_practice/features/switch_tutorial_page.dart';
import 'package:piano_practice/features/training_page.dart';

import '../domain/task_engine_test.dart' show create, ready;

class _SignalController extends AppController {
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    content.config = create(clock).config;
    engine = TaskEngine(
      config: content.config,
      clock: clock,
      taskId: taskId,
      mode: 'ASSIST',
      level: 1,
      song: [],
      layoutSnapshot: keyboardLayout,
      seed: 47,
    );
    layout = keyboardLayout;
    ready(engine!, clock);
    notifyListeners();
  }
}

void mocks(
  WidgetTester tester,
  Size size,
  String locale,
  double scale,
  AppController c,
) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('piano_training/platform/v1'),
        (call) async => {
          'ok': true,
          'request_id': (call.arguments as Map)['request_id'],
          'data': <String, dynamic>{},
        },
      );
  c.initialized = true;
  c.audioReady = true;
  c.repository.profile = {
    'locale': locale,
    'mode': 'ASSIST',
    'onboarding_completed': 1,
    'settings_json': jsonEncode({
      'high_contrast': false,
      'sound_enabled': false,
      'gain_permille': 600,
    }),
  };
}

void main() {
  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    for (final size in [const Size(640, 360), const Size(800, 360)]) {
      for (final locale in ['zh-Hans', 'en']) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '$task signals, pause and results ${size.width} $locale $scale',
            (tester) async {
              final c = _SignalController();
              mocks(tester, size, locale, scale, c);
              await tester.pumpWidget(PianoApp(controller: c));
              tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => TrainingPage(c: c, taskId: task),
                    ),
                  );
              await tester.pumpAndSettle();
              await tester.pump(const Duration(seconds: 1));
              await tester.pumpAndSettle();
              expect(c.engine, isNotNull);
              expect(tester.takeException(), isNull);
              if (task == 'G3_SWITCH') {
                expect(find.byType(SignalSlots).hitTestable(), findsOneWidget);
                expect(find.byType(ShapeMark), findsNWidgets(4));
                expect(
                  find
                      .text(
                        locale == 'en'
                            ? 'Rule A · Match position'
                            : '规则 A · 按位置',
                      )
                      .hitTestable(),
                  findsOneWidget,
                );
              } else {
                final e = c.engine!, clock = c.engine!.clock as ManualClock;
                while (e.target['trial_type'] != 'NO_GO') {
                  clock.now += e.responseWindowUs;
                  e.tick();
                  ready(e, clock);
                }
                c.notifyListeners();
                await tester.pumpAndSettle();
                expect(find.byType(RestMark).hitTestable(), findsOneWidget);
              }
              c.engine!.pause('USER');
              c.notifyListeners();
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('pause-menu')), findsOneWidget);
              expect(find.text('继续练习'), findsNothing);
              final e = c.engine!;
              e.finish('EXITED');
              tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => ResultPage(
                        c: c,
                        record: {
                          'task_id': task,
                          'status': 'EXITED',
                          'parameter_profile_version': 'demo',
                          'metric_version': 'metrics-1.0.0',
                          'mode': 'ASSIST',
                          'result_json': canonical(e.summary()),
                        },
                      ),
                    ),
                  );
              await tester.pumpAndSettle();
              final details = find.text(
                locale == 'en' ? 'Practice details' : '详细训练表现',
              );
              await tester.scrollUntilVisible(
                details,
                120,
                scrollable: find
                    .descendant(
                      of: find.byType(ResultPage),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              await Scrollable.ensureVisible(
                tester.element(details),
                alignment: .3,
              );
              await tester.pumpAndSettle();
              await tester.tap(details);
              await tester.pumpAndSettle();
              for (final metric
                  in find.byType(MetricRate).evaluate().toList()) {
                await tester.ensureVisible(find.byWidget(metric.widget));
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
              await tester.pumpWidget(const SizedBox());
              c.dispose();
              await tester.pump();
            },
          );
        }
      }
    }
  }
  for (final locale in ['zh-Hans', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('four unscored examples layout $locale $scale', (
        tester,
      ) async {
        final c = AppController();
        mocks(tester, const Size(360, 640), locale, scale, c);
        await tester.pumpWidget(PianoApp(controller: c));
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(builder: (_) => SwitchTutorialPage(c: c)),
            );
        await tester.pumpAndSettle();
        final slots = find.byType(SignalSlots);
        await tester.scrollUntilVisible(
          slots,
          120,
          scrollable: find
              .descendant(
                of: find.byType(SwitchTutorialPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump();
      });
    }
  }
}
