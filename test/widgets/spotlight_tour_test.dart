import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/ui/spotlight_tour.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

Future<void> advance(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'spotlight passes target taps, blocks other controls, and saves completion',
    (tester) async {
      final repo = MemoryPreferences();
      final c = AppController(repository: repo);
      mocks(tester, const Size(400, 800), 'zh-Hans', 1, c);
      repo.profile['settings_json'] = canonical({
        ...c.settings,
        'spotlight_guides_enabled': true,
      });
      final target = GlobalKey();
      var taps = 0, blocked = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: SpotlightTour(
            c: c,
            preferenceKey: 'guide-test',
            steps: [
              SpotlightStep(target: target, title: '引导目标', message: '点击圆圈中的按钮'),
            ],
            child: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    key: target,
                    onPressed: () => taps++,
                    child: const Text('高亮按钮'),
                  ),
                  const SizedBox(height: 100),
                  ElevatedButton(
                    onPressed: () => blocked++,
                    child: const Text('遮罩外按钮'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await advance(tester);
      expect(find.textContaining('引导目标'), findsOneWidget);
      await tester.tap(find.text('遮罩外按钮'), warnIfMissed: false);
      await advance(tester);
      expect(blocked, 0);
      await tester.tap(find.text('高亮按钮'));
      await advance(tester);
      expect(taps, 1);
      expect(c.settings['guide-test'], true);
      expect(find.byKey(const ValueKey('spotlight-next')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('skip persists and a saved guide does not start again', (
    tester,
  ) async {
    final repo = MemoryPreferences();
    final c = AppController(repository: repo);
    mocks(tester, const Size(320, 640), 'zh-Hans', 2, c);
    repo.profile['settings_json'] = canonical({
      ...c.settings,
      'spotlight_guides_enabled': true,
    });
    final target = GlobalKey();
    Widget host() => MaterialApp(
      theme: qinTheme(highContrast: false),
      home: SpotlightTour(
        c: c,
        preferenceKey: 'guide-test',
        steps: [
          SpotlightStep(
            target: target,
            title: '欢迎',
            message: '一段较长的教学文字，用于验证大字号时说明面板可以滚动。',
          ),
        ],
        child: Scaffold(
          body: Center(child: SizedBox(key: target, width: 60, height: 60)),
        ),
      ),
    );
    await tester.pumpWidget(host());
    await advance(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('spotlight-skip')));
    await tester.tap(find.byKey(const ValueKey('spotlight-skip')));
    await advance(tester);
    expect(c.settings['guide-test'], true);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    await advance(tester);
    expect(find.byKey(const ValueKey('spotlight-next')), findsNothing);
    await c.updateSettings(values: {'guide-test': false});
    await tester.pumpWidget(host());
    await advance(tester);
    expect(find.byKey(const ValueKey('spotlight-next')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spotlight-skip')));
    await advance(tester);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('rounded highlight allows taps across the full wide control', (
    tester,
  ) async {
    final repo = MemoryPreferences();
    final c = AppController(repository: repo);
    mocks(tester, const Size(400, 800), 'zh-Hans', 1, c);
    repo.profile['settings_json'] = canonical({
      ...c.settings,
      'spotlight_guides_enabled': true,
    });
    final target = GlobalKey();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: SpotlightTour(
          c: c,
          preferenceKey: 'rectangle-test',
          steps: [
            SpotlightStep(
              target: target,
              shape: SpotlightShape.roundedRectangle,
              advanceOnTap: false,
              title: '调整整组控件',
              message: '整个区域都可操作',
            ),
          ],
          child: Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => taps++,
                child: SizedBox(
                  key: target,
                  width: 300,
                  height: 80,
                  child: const ColoredBox(color: Colors.green),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await advance(tester);
    final rect = tester.getRect(find.byKey(target));
    await tester.tapAt(Offset(rect.left + 12, rect.center.dy));
    await advance(tester);
    await tester.tapAt(Offset(rect.right - 12, rect.center.dy));
    await advance(tester);
    expect(taps, 2);
    expect(find.byKey(const ValueKey('spotlight-next')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spotlight-skip')));
    await advance(tester);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'explanation-only step does not expose an interactive spotlight',
    (tester) async {
      final repo = MemoryPreferences();
      final c = AppController(repository: repo);
      mocks(tester, const Size(800, 400), 'zh-Hans', 1, c);
      repo.profile['settings_json'] = canonical({
        ...c.settings,
        'spotlight_guides_enabled': true,
      });
      var taps = 0;
      final target = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: SpotlightTour(
            c: c,
            preferenceKey: 'no-highlight-test',
            steps: const [
              SpotlightStep(
                shape: SpotlightShape.none,
                title: '看提示符下落',
                message: '训练开始后，长条会从上方落向对应琴键。长条越长，需要按住的时间越久。',
              ),
            ],
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: ElevatedButton(
                  key: target,
                  onPressed: () => taps++,
                  child: const Text('背景按钮'),
                ),
              ),
            ),
          ),
        ),
      );
      await advance(tester);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .maxScrollExtent,
        0,
      );
      await tester.tap(find.byKey(target), warnIfMissed: false);
      await advance(tester);
      expect(taps, 0);
      await tester.tap(find.byKey(const ValueKey('spotlight-next')));
      await advance(tester);
      expect(c.settings['no-highlight-test'], true);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
