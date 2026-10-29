import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

void main() {
  testWidgets(
    'display description is concise and about page reflects current features',
    (tester) async {
      final c = AppController(repository: MemoryPreferences());
      mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final desc = find.text('可关闭摆锤等装饰运动。');
      final scroll = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .last;
      await tester.scrollUntilVisible(desc, 250, scrollable: scroll);
      expect(desc, findsOneWidget);
      expect(find.textContaining('保留拍点、琴键和练习进度'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: AboutPage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('六首钢琴曲目'), findsOneWidget);
      expect(find.textContaining('速度记忆'), findsOneWidget);
      expect(find.textContaining('五键简化编配'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump();
    },
  );
}
