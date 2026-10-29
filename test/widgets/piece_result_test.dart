import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/piece_result_page.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import '../domain/piece_performance_test.dart' show completedRecord;
import 'cognitive_pages_test.dart' show mocks;
import 'piano_pieces_page_test.dart' show frames, remove;
import 'rhythm_pages_test.dart' show MemoryPreferences;

class PieceMemory extends MemoryPreferences {
  final records = <String, Json>{};
  int saves = 0;
  bool fail = false;
  @override
  Future<void> savePiecePerformance(Json record) async {
    saves++;
    if (fail) throw StateError('disk full');
    PiecePerformance.validate(record);
    records[record['session_id'] as String] = {...record};
  }

  @override
  Future<HistoryPage> historyPage({Json? after}) async => HistoryPage([
    for (final r in records.values)
      {
        ...r,
        'task_id': 'PIANO_PIECE',
        'status': 'COMPLETED',
        'result_json': canonical(r),
      },
  ], false);
}

Future<void> scrollTo(WidgetTester tester, Finder target, double delta) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
}

void main() {
  testWidgets('performance automatically opens completion and saves once', (
    tester,
  ) async {
    final repo = PieceMemory();
    final clock = ManualClock();
    final c = AppController(clock: clock, repository: repo);
    addTearDown(c.dispose);
    mocks(tester, const Size(800, 360), 'zh-Hans', 1, c);
    await tester.runAsync(c.content.load);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PianoPerformancePage(
          c: c,
          piece: c.content.pieces.first,
          tempo: 60,
        ),
      ),
    );
    await frames(tester);
    clock.now = 4000000;
    await tester.pump(const Duration(milliseconds: 16));
    final key = tester.getRect(find.byType(PianoKeyboard)).center;
    await tester.tapAt(key);
    clock.now =
        4000000 +
        c.content.pieces.first.ticks *
            1000000 ~/
            c.content.pieces.first.ticksPerBeat;
    await frames(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PieceResultPage), findsOneWidget);
    expect(find.text('已保存记录'), findsOneWidget);
    expect(repo.records.values.single['matched_notes'], [0]);
    expect(repo.saves, 1);
    await frames(tester);
    expect(repo.saves, 1);
    expect(c.history.single['task_id'], 'PIANO_PIECE');
    await remove(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: ResultPage(c: c, record: c.history.single),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PieceResultPage), findsOneWidget);
    expect(repo.saves, 1);
    expect(find.textContaining('旧版'), findsNothing);
    await remove(tester);
  });

  testWidgets('save failure is visible and retry keeps a single record ID', (
    tester,
  ) async {
    final repo = PieceMemory()..fail = true;
    final c = AppController(repository: repo);
    addTearDown(c.dispose);
    mocks(tester, const Size(360, 640), 'zh-Hans', 2, c);
    await tester.runAsync(c.content.load);
    final record = completedRecord();
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: true),
        home: PieceResultPage(c: c, record: record),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('记录尚未保存，请重试。'), findsOneWidget);
    expect(repo.records, isEmpty);
    repo.fail = false;
    await scrollTo(tester, find.text('重试保存'), 120);
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('已保存记录'), -120);
    expect(find.text('已保存记录'), findsOneWidget);
    expect(repo.records.keys.single, record['session_id']);
    expect(repo.saves, 2);
    expect(tester.takeException(), isNull);
    await remove(tester);
  });

  testWidgets(
    'library shows composer only and tempo readout is left of slider',
    (tester) async {
      final c = AppController(repository: PieceMemory());
      addTearDown(c.dispose);
      mocks(tester, const Size(360, 640), 'zh-Hans', 1, c);
      await tester.runAsync(c.content.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPiecesPage(c: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('贝多芬'), findsOneWidget);
      expect(find.textContaining('先选速度'), findsNothing);
      expect(find.text('选择速度'), findsNothing);
      expect(find.textContaining('8 小节'), findsNothing);
      await tester.tap(find.text('欢乐颂'));
      await tester.pumpAndSettle();
      final label = tester.getRect(
        find.byKey(const ValueKey('piece-tempo-label')),
      );
      final slider = tester.getRect(find.byKey(const ValueKey('piece-tempo')));
      expect(label.right, lessThan(slider.left));
      expect(label.center.dy, closeTo(slider.center.dy, 1));
      await remove(tester);
    },
  );
}
