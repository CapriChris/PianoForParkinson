import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/training_page.dart';

import '../domain/task_engine_test.dart' show create;

class PausedController extends AppController {
  PausedController(this.failSave);
  final bool failSave;
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    engine = TaskEngine(
      config: create(ManualClock()).config,
      clock: ManualClock(),
      taskId: taskId,
      mode: 'ASSIST',
      level: 1,
      song: [0, 1],
      layoutSnapshot: keyboardLayout,
    );
    layout = keyboardLayout;
    engine!.pause('USER');
    if (failSave) storageError = 'injected write failure';
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(640, 360), const Size(800, 360)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('inline pause menu ${size.width} $locale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                SystemChannels.platform,
                (_) async => null,
              );
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
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
          final c = PausedController(scale == 2);
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
          await tester.pumpWidget(PianoApp(controller: c));
          await tester.pumpAndSettle();
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => TrainingPage(c: c, taskId: 'G1_MEMORY'),
                ),
              );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          for (var i = 0; i < 20 && c.engine == null; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final dynamic trainingState = tester.state(find.byType(TrainingPage));
          expect(
            c.engine,
            isNotNull,
            reason:
                'ready=${trainingState.ready}, orientation=${trainingState.orientationRequested}, animation=${trainingState.routeAnimation?.status}; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).join('; ')}',
          );
          expect(find.byKey(const ValueKey('pause-menu')), findsOneWidget);
          expect(
            find.text(locale == 'zh-Hans' ? '需要帮助' : 'Need help'),
            findsNothing,
          );
          expect(
            find.text(locale == 'zh-Hans' ? '返回首页' : 'Home'),
            findsNothing,
          );
          expect(find.text('继续练习'), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('pause-toggle')),
              matching: find.text(locale == 'zh-Hans' ? '继续' : 'Continue'),
            ),
            findsOneWidget,
          );
          final panelRect = tester.getRect(
            find.byKey(const ValueKey('pause-menu')),
          );
          final keyboard = c.layout!['keyboard_rect'] as List;
          if (scale == 1) {
            expect(panelRect.bottom, lessThanOrEqualTo(keyboard[1] / 1000));
          }
          expect(panelRect.top, lessThan(keyboard[1] / 1000));
          final labels = locale == 'zh-Hans'
              ? [if (scale == 2) '重试保存', '重看演示', '增加帮助', '结束本次']
              : [
                  if (scale == 2) 'Retry saving',
                  'Replay demo',
                  'More help',
                  'End practice',
                ];
          for (final label in labels) {
            final finder = find.descendant(
              of: find.byKey(const ValueKey('pause-menu')),
              matching: find.text(label),
            );
            if (scale == 1) expect(finder.hitTestable(), findsOneWidget);
            await Scrollable.ensureVisible(
              tester.element(finder),
              alignment: .2,
            );
            await tester.pumpAndSettle();
            expect(finder.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          await tester.pump();
        });
      }
    }
  }
}
