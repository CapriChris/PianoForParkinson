import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/ui/qin_dialog.dart';
import 'package:piano_practice/ui/qin_press.dart';
import 'package:piano_practice/ui/qin_theme.dart';

void main() {
  for (final chinese in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      for (final size in [const Size(320, 640), const Size(640, 320)]) {
        testWidgets(
          'dialog actions share a row and remain usable $chinese $scale $size',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            bool? choice;
            await tester.pumpWidget(
              MaterialApp(
                theme: qinTheme(highContrast: false),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: QinTextButton(
                      onPressed: () async {
                        choice = await showDialog<bool>(
                          context: context,
                          builder: (context) => QinDialog(
                            title: Text(
                              chinese ? '退出本次练习？' : 'Exit this practice?',
                            ),
                            content: Text(
                              chinese ? '退出不会保存本次训练记录。' : 'Your training record will not be saved if you exit.',
                            ),
                            actions: [
                              QinTextButton(
                                key: const ValueKey('left'),
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  chinese ? '继续练习' : 'Continue practice',
                                ),
                              ),
                              QinFilledButton(
                                key: const ValueKey('right'),
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(chinese ? '退出' : 'Exit'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final left = find.byKey(const ValueKey('left')),
                right = find.byKey(const ValueKey('right'));
            await tester.ensureVisible(right);
            await tester.pumpAndSettle();
            final a = tester.getRect(left), b = tester.getRect(right);
            expect(a.width, closeTo(b.width, .01));
            expect(a.top, closeTo(b.top, .01));
            expect(a.height, closeTo(b.height, .01));
            expect(a.right, lessThan(b.left));
            final button = find.descendant(
              of: left,
              matching: find.byType(TextButton),
            );
            expect(
              TextButtonTheme.of(tester.element(button)).style!.side!
                  .resolve({})!
                  .width,
              greaterThan(0),
            );
            expect(right.hitTestable(), findsOneWidget);
            await tester.tap(right);
            await tester.pumpAndSettle();
            expect(choice, isTrue);
            expect(find.byType(AlertDialog), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
