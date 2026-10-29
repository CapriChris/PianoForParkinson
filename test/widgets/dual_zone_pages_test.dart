import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:piano_practice/features/touch_check_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/training_page.dart';

import '../domain/dual_zone_test.dart' show dual;
import '../domain/task_engine_test.dart' show ready;
import 'cognitive_pages_test.dart' show mocks;

class DualController extends AppController {
  @override
  Future<void> flush() async {}
  @override
  Future<void> start(
    String taskId,
    Json keyboardLayout, {
    bool reader = false,
  }) async {
    final clock = ManualClock();
    engine = dual(clock)..layoutSnapshot = keyboardLayout;
    content.config = engine!.config;
    layout = keyboardLayout;
    ready(engine!, clock);
    notifyListeners();
  }
}

void main() {
  for (final size in [const Size(800, 360), const Size(1280, 800)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'dual six keys, two targets and pause $size $locale $scale',
          (tester) async {
            final c = DualController();
            mocks(tester, size, locale, scale, c);
            await tester.pumpWidget(PianoApp(controller: c));
            tester
                .state<NavigatorState>(find.byType(Navigator))
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrainingPage(c: c, taskId: 'M2_DUAL_ZONE'),
                  ),
                );
            await tester.pumpAndSettle();
            final keyboard = tester.widget<PianoKeyboard>(
              find.byType(PianoKeyboard),
            );
            expect(keyboard.count, 6);
            expect(keyboard.active, {0, 1, 2, 3, 4, 5});
            expect(keyboard.highlightedKeys, {0, 3});
            expect(c.layout!['layout_id'], 'DUAL_ZONE_SIX_KEYS');
            expect(tester.takeException(), isNull);
            c.pause('USER');
            await tester.pumpAndSettle();
            expect(
              find.text(locale == 'en' ? 'Practice paused' : '练习已暂停'),
              findsOneWidget,
            );
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
  for (final locale in ['zh-Hans', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'portrait M2 entry, required check, native proof and direct continuation $locale $scale',
        (tester) async {
          final c = DualController();
          mocks(tester, const Size(360, 800), locale, scale, c);
          var nativePoints = 0;
          final orientations = <Object?>[];
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, (call) async {
                if (call.method == 'SystemChrome.setPreferredOrientations') {
                  orientations.add(call.arguments);
                }
                return null;
              });
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('piano_training/platform/v1'),
                (call) async => {
                  'ok': true,
                  'request_id': (call.arguments as Map)['request_id'],
                  'data': call.method == 'getCapabilities'
                      ? {
                          'touch2_supported': true,
                          'max_verified_touch_points': nativePoints,
                        }
                      : <String, dynamic>{},
                },
              );
          c.capabilities = {
            'touch2_supported': false,
            'max_verified_touch_points': 0,
          };
          await tester.pumpWidget(PianoApp(controller: c));
          final entry = find.text(c.text('练习双区', 'Practice two zones'));
          await tester.scrollUntilVisible(
            entry.hitTestable(),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.text(c.text('双区配合', 'Two-zone coordination')),
            findsOneWidget,
          );
          expect(
            find.text(c.text('检查双触点支持', 'Check two-touch support')),
            findsNothing,
          );
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(find.byType(TouchCheckPage), findsOneWidget);
          expect(find.byType(InstructionPage), findsNothing);
          expect(orientations.last, [
            'DeviceOrientation.landscapeLeft',
            'DeviceOrientation.landscapeRight',
          ]);
          tester.view.physicalSize = const Size(800, 360);
          await tester.pumpAndSettle();
          final finish = find.widgetWithText(
            FilledButton,
            c.text('完成检查，继续', 'Continue after check'),
          );
          expect(tester.widget<FilledButton>(finish).onPressed, isNull);
          final left = find.byKey(const ValueKey('touch-check-left'));
          final right = find.byKey(const ValueKey('touch-check-right'));
          await tester.ensureVisible(left);
          await tester.pumpAndSettle();
          Future<void> touchPair() async {
            final a = await tester.startGesture(
              tester.getCenter(left),
              pointer: 10,
            );
            final b = await tester.startGesture(
              tester.getCenter(right),
              pointer: 11,
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<FilledButton>(finish).onPressed,
              nativePoints >= 2 ? isNotNull : isNull,
            );
            await a.up();
            await b.up();
            await tester.pumpAndSettle();
          }

          await touchPair(); // Two Dart gestures cannot substitute for native confirmation.
          nativePoints = 2;
          await touchPair();
          await tester.tap(finish);
          await tester.pumpAndSettle();
          expect(find.byType(InstructionPage), findsOneWidget);
          expect(find.byType(TouchCheckPage), findsNothing);
          expect(c.engine, isNull); // The check never creates a scored session.
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();
          expect(orientations.last, contains('DeviceOrientation.portraitUp'));
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
  for (final reader in [false, true]) {
    testWidgets(
      'check cannot continue in narrow window or with screen reader reader=$reader',
      (tester) async {
        final c = DualController();
        final size = reader ? const Size(800, 360) : const Size(360, 800);
        mocks(tester, size, 'en', 1, c);
        c.capabilities = {'max_verified_touch_points': 2};
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size, accessibleNavigation: reader),
              child: TouchCheckPage(
                c: c,
                onContinue: () => fail('Must remain blocked'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(c.engine, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
