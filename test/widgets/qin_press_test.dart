import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/ui/qin_press.dart';
import 'package:piano_practice/ui/qin_theme.dart';
import 'package:piano_practice/ui/qin_components.dart';

void main() {
  for (final iconSize in [18.0, 24.0]) {
    testWidgets(
      'icon surface is a compact circle with a padded tap target $iconSize',
      (tester) async {
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: Scaffold(
              body: Center(
                child: QinIconButton(
                  key: const ValueKey('compact-icon'),
                  tooltip: 'Close',
                  style: IconButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => calls++,
                  icon: Icon(Icons.close, size: iconSize),
                ),
              ),
            ),
          ),
        );
        final button = find.byKey(const ValueKey('compact-icon'));
        final surface = find.descendant(
          of: button,
          matching: find.byType(Material),
        );
        expect(tester.widget<Material>(surface).shape, isA<CircleBorder>());
        expect(tester.getSize(surface), Size.square(iconSize + 12));
        expect(tester.getSize(button), const Size.square(48));
        await tester.tapAt(tester.getTopLeft(button) + const Offset(2, 24));
        await tester.pumpAndSettle();
        expect(calls, 1);
      },
    );
  }
  testWidgets('entry card border scales together with content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: QinEntryCard(
                icon: Icons.piano,
                title: 'Card',
                subtitle: 'Details',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final border = find.byType(Card);
    final before = tester.getRect(border);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final pressed = tester.getRect(border);
    expect(pressed.width, lessThan(before.width));
    expect(pressed.height, lessThan(before.height));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(border).width, closeTo(before.width, .01));
  });
  testWidgets(
    'native switch changes without animating or activating its card',
    (tester) async {
      var enabled = true, opens = 0, batches = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: SizedBox(
                  width: 300,
                  child: QinInkWell(
                    surfaceBuilder: (surface) => Card(child: surface),
                    onTap: () => opens++,
                    onLongPress: () => batches++,
                    child: Row(
                      children: [
                        const Expanded(child: Text('Plan')),
                        QinPressBlock(
                          child: Switch(
                            value: enabled,
                            onChanged: (v) => setState(() => enabled = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byType(Card));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Switch)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.byType(Card)), before);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(enabled, isFalse);
      expect(opens, 0);
      expect(batches, 0);
      await tester.longPress(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(batches, 0);
    },
  );

  testWidgets(
    'press scales before action, waits for release and ignores disabled buttons',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            body: Center(
              child: QinFilledButton(
                onPressed: () => actions++,
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(QinPress),
          matching: find.byType(Transform),
        ),
      );
      expect(transforms.any((w) => w.transform.storage[0] < 1), isTrue);
      expect(actions, 0);
      await gesture.up();
      expect(actions, 0);
      await tester.pumpAndSettle();
      expect(actions, 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Scaffold(
            body: QinFilledButton(
              onPressed: null,
              child: const Text('Disabled'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(actions, 1);
    },
  );
  testWidgets('system reduced motion does not delay the action', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: QinTextButton(
              onPressed: () => actions++,
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    expect(actions, 1);
  });
}
