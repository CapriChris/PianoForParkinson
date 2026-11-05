import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/features/training_page.dart';

import 'training_panel_test.dart' show PausedController;

class ExitController extends PausedController {
  ExitController() : super(false);
  int saves = 0, discards = 0;
  bool failDiscard = false;

  @override
  Future<void> exit() async {
    saves++;
    engine!.finish('EXITED');
    saved = true;
    notifyListeners();
  }

  @override
  Future<void> discardPractice() async {
    discards++;
    if (failDiscard) throw StateError('injected');
    engine = null;
    layout = null;
    notifyListeners();
    trainingUpdates.value++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final choice in ['保存', '不保存', '取消', '失败重试']) {
    testWidgets('exit training: $choice', (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      const channel = MethodChannel('piano_training/platform/v1');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {
          'ok': true,
          'request_id': (call.arguments as Map)['request_id'],
          'data': <String, dynamic>{},
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        messenger.setMockMethodCallHandler(channel, null);
      });
      final c = ExitController()
        ..initialized = true
        ..audioReady = true;
      c.repository.profile = {
        'locale': 'zh-Hans',
        'mode': 'ASSIST',
        'onboarding_completed': 1,
        'settings_json': jsonEncode({
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
      expect(c.engine, isNotNull);
      final id = c.engine!.id;
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('退出本次训练'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '不保存'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
      if (choice == '取消') {
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
        expect(c.engine!.id, id);
        expect(c.saves + c.discards, 0);
        expect(find.byType(TrainingPage), findsOneWidget);
      } else {
        if (choice == '失败重试') c.failDiscard = true;
        await tester.tap(find.text(choice == '保存' ? '保存' : '不保存'));
        await tester.pumpAndSettle();
        if (choice == '失败重试') {
          expect(c.engine!.id, id);
          expect(find.text('暂时无法退出，请重试。'), findsOneWidget);
          c.failDiscard = false;
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('不保存'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(TrainingPage), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);
        expect(c.saves, choice == '保存' ? 1 : 0);
        expect(
          c.discards,
          choice == '保存'
              ? 0
              : choice == '失败重试'
              ? 2
              : 1,
        );
        expect(c.saved, choice == '保存');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump();
    });
  }
}
