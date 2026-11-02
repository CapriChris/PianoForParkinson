import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/features/dance_result_page.dart';
import 'package:piano_practice/features/song_library_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

Json danceRecord() => {
  'session_id': 'historic-dance',
  'content_id': 'hkpdf-balance-six',
  'title': '新平衡舞步六式',
  'title_zh': '新平衡舞步六式',
  'title_en': 'Six balance dance steps',
  'started_utc_ms': DateTime.utc(2026, 11, 2, 4).millisecondsSinceEpoch,
  'utc_offset_minutes': 480,
  'active_ms': 62000,
  'covered_ms': 62000,
  'parts': [
    {'title': '第一部分', 'active_ms': 60000, 'reached_end': true},
    {'title': '第二部分', 'active_ms': 2000, 'reached_end': false},
    {'title': '第三部分', 'active_ms': 0, 'reached_end': false},
  ],
};

class DanceHistoryMemory extends MemoryPreferences {
  @override
  Future<HistoryPage> historyPage({Json? after}) async => HistoryPage([
    {
      'session_id': 'historic-dance',
      'task_id': 'DANCE',
      'status': 'COMPLETED',
      'content_id': 'hkpdf-balance-six',
      'started_utc_ms': danceRecord()['started_utc_ms'],
      'session_utc_offset_minutes': 480,
      'result_json': canonical(danceRecord()),
    },
  ], false);
}

Json categoryRecord(String id, String task) => {
  'session_id': id,
  'task_id': task,
  'status': 'COMPLETED',
  'content_id': task == 'DANCE' ? 'hkpdf-balance-six' : null,
  'started_utc_ms': DateTime.utc(2026, 11, 2, 4).millisecondsSinceEpoch,
  'session_utc_offset_minutes': 480,
  'result_json': canonical(
    task == 'DANCE'
        ? danceRecord()
        : {
            'total_notes': 1,
            'matched_notes': [0],
            'rates': {
              'primary': {'numerator': 1, 'denominator': 1},
            },
          },
  ),
};

class CategoryHistoryMemory extends MemoryPreferences {
  int reads = 0;
  bool failNextPage = false;
  final pages = [
    [
      categoryRecord('exercise-new', 'G1_MEMORY'),
      categoryRecord('piece', 'PIANO_PIECE'),
    ],
    [categoryRecord('exercise-old', 'S1_GUIDED')],
    [categoryRecord('dance-old', 'DANCE')],
  ];
  @override
  Future<HistoryPage> historyPage({Json? after}) async {
    reads++;
    if (after != null && failNextPage) {
      failNextPage = false;
      throw StateError('Temporary read failure');
    }
    final index = after == null
        ? 0
        : pages.indexWhere(
                (page) => page.last['session_id'] == after['session_id'],
              ) +
              1;
    return HistoryPage(pages[index], index < pages.length - 1);
  }
}

void main() {
  void setup(
    WidgetTester tester,
    AppController c,
    Size size,
    String locale,
    double scale,
  ) {
    addTearDown(c.dispose);
    mocks(tester, size, locale, scale, c);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform_events/v1'),
          (_) async => null,
        );
  }

  for (final fail in [false, true]) {
    testWidgets(
      'history categories find older matching records across pages, retry=$fail',
      (tester) async {
        final repository = CategoryHistoryMemory()..failNextPage = fail;
        final c = AppController(repository: repository);
        setup(tester, c, const Size(390, 844), 'zh-Hans', 1);
        await tester.runAsync(c.content.load);
        await c.refreshHistory();
        await tester.pumpWidget(
          MaterialApp(
            theme: qinTheme(highContrast: false),
            home: Scaffold(body: HistoryList(c: c)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('舞蹈记录'), findsNothing);
        final scroll = find.byType(Scrollable).last;
        Future<void> select(String category) async {
          final chip = find.byKey(ValueKey('history-category-$category'));
          await tester.ensureVisible(chip);
          await tester.pumpAndSettle();
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        }

        await select('exercises');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('history-record-exercise-new')),
          120,
          scrollable: scroll,
        );
        expect(
          find.byKey(const ValueKey('history-record-piece')),
          findsNothing,
        );
        await select('pieces');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('history-record-piece')),
          120,
          scrollable: scroll,
        );
        expect(
          find.byKey(const ValueKey('history-record-exercise-new')),
          findsNothing,
        );
        await select('dance');
        if (fail) {
          final retry = find.text('重试');
          await tester.ensureVisible(retry);
          await tester.pumpAndSettle();
          await tester.tap(retry);
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('history-record-dance-old')),
          120,
          scrollable: scroll,
        );
        expect(repository.reads, fail ? 4 : 3);
        expect(c.history.length, 4);
        expect(
          find.byKey(const ValueKey('history-record-exercise-old')),
          findsNothing,
        );
        await select('recent');
        expect(c.historyHasMore, isFalse);
        expect(c.historyError, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('an empty history category finishes paging at large text', (
    tester,
  ) async {
    final repository = CategoryHistoryMemory()..pages.removeLast();
    final c = AppController(repository: repository);
    setup(tester, c, const Size(320, 640), 'zh-Hans', 2);
    await tester.runAsync(c.content.load);
    await c.refreshHistory();
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: Scaffold(body: HistoryList(c: c)),
      ),
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('history-category-dance'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    final categoryBounds = [
      for (final category in ['recent', 'exercises', 'pieces', 'dance'])
        tester.getRect(find.byKey(ValueKey('history-category-$category'))),
    ];
    for (final rect in categoryBounds) {
      expect(rect.top, closeTo(categoryBounds.first.top, 1));
      expect(rect.width, closeTo(categoryBounds.first.width, 1));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    for (final category in ['recent', 'exercises', 'pieces', 'dance']) {
      final chip = find.byKey(ValueKey('history-category-$category'));
      final material = find
          .descendant(of: chip, matching: find.byType(Material))
          .first;
      expect(
        tester.getRect(material).width,
        closeTo(categoryBounds.first.width, 1),
      );
    }
    expect(find.text('全部'), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('暂无这类练习记录'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(c.historyHasMore, isFalse);
    expect(repository.reads, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'recent dance opens saved details without writing and Home returns to the home tab',
    (tester) async {
      final c = AppController(repository: DanceHistoryMemory());
      setup(tester, c, const Size(390, 844), 'zh-Hans', 1);
      await tester.runAsync(c.content.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: HomePage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('记录').last);
      await tester.pumpAndSettle();
      final title = find.text('新平衡舞步六式');
      await tester.scrollUntilVisible(
        title,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DanceResultPage>(find.byType(DanceResultPage))
            .alreadySaved,
        isTrue,
      );
      expect(find.text('已保存训练记录'), findsOneWidget);
      expect(find.text('2026-11-02 12:00'), findsOneWidget);
      final repeat = tester.getRect(
        find.byKey(const ValueKey('dance-practise-again')),
      );
      final home = tester.getRect(find.byKey(const ValueKey('dance-home')));
      expect(repeat.left, lessThan(home.left));
      expect(repeat.top, closeTo(home.top, 1));
      await tester.tap(find.byKey(const ValueKey('dance-home')));
      await tester.pumpAndSettle();
      expect(find.byType(DanceResultPage), findsNothing);
      expect(find.byType(HistoryList), findsNothing);
      expect(c.homeNavigationRequests.value, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in ['zh-Hans', 'en']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'saved dance details keep both footer actions on one row at 320dp $locale $scale',
        (tester) async {
          final c = AppController();
          setup(tester, c, const Size(320, 640), locale, scale);
          await tester.pumpWidget(
            MaterialApp(
              theme: qinTheme(highContrast: false),
              home: DanceResultPage(
                c: c,
                record: danceRecord(),
                alreadySaved: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final repeat = tester.getRect(
            find.byKey(const ValueKey('dance-practise-again')),
          );
          final home = tester.getRect(find.byKey(const ValueKey('dance-home')));
          expect(repeat.top, closeTo(home.top, 1));
          expect(home.right, lessThanOrEqualTo(320));
          expect(repeat.left, greaterThanOrEqualTo(0));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('short melody and rhythm lists no longer show credits sections', (
    tester,
  ) async {
    final c = AppController();
    setup(tester, c, const Size(390, 844), 'zh-Hans', 1);
    await tester.runAsync(c.content.load);
    for (final task in ['S1_GUIDED', 'S2_RHYTHM']) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(task),
          theme: qinTheme(highContrast: false),
          home: SongLibraryPage(c: c, taskId: task),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容与来源'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
