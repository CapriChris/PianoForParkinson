import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/hand_cue.dart';

void main() {
  for (final task in ['M1_ALTERNATE', 'M2_DUAL_ZONE']) {
    for (final language in ['zh', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$task $language scale$scale readable hand labels map to real keys',
          (tester) async {
            tester.view.physicalSize = const Size(640, 360);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final count = task == 'M1_ALTERNATE' ? 2 : 6;
            final input = <int>[];
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(language),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Column(
                    children: [
                      HandCue(
                        hand: PracticeHand.left,
                        chinese: language == 'zh',
                        keyNumber: 1,
                      ),
                      SizedBox(
                        height: 110,
                        child: PianoKeyboard(
                          count: count,
                          handTaskId: task,
                          active: Set.from(List.generate(count, (i) => i)),
                          highlighted: count - 1,
                          onDown: (_, k, _, _) {
                            if (k != null) input.add(k);
                          },
                          onUp: (_, _, _, _) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              find.text(language == 'zh' ? '左手' : 'Left hand'),
              findsWidgets,
            );
            expect(
              find.text(language == 'zh' ? '右手' : 'Right hand'),
              findsWidgets,
            );
            await tester.tap(find.byKey(const ValueKey('key-feedback-0')));
            await tester.tap(find.byKey(ValueKey('key-feedback-${count - 1}')));
            expect(input, [0, count - 1]);
            final left = tester.getRect(
              find.byKey(const ValueKey('key-feedback-0')),
            );
            expect(left.width, greaterThanOrEqualTo(60));
            expect(left.height, greaterThanOrEqualTo(96));
            expect(handForKey(task, 0), PracticeHand.left);
            expect(handForKey(task, count - 1), PracticeHand.right);
            expect(handForKey('G3_SWITCH', 0), isNull);
            expect(PracticeHand.left.color, const Color(0xFF1D4ED8));
            expect(PracticeHand.right.color, const Color(0xFFC2410C));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
