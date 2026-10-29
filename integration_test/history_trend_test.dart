import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/trend_page.dart';

import 'android_contract_test.dart' show advance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AppController c;
  late Directory directory;
  setUp(() async {
    c = AppController(databaseSubdirectory: 'history-${uuid()}');
    await c.initialize();
    expect(c.error, isNull);
    expect(c.capabilities['audio_route_category'], 'BUILT_IN');
    await c.updateSettings(locale: 'en', onboard: true);
    directory = Directory(
      (await c.platform.call('getCapabilities'))['storage_path'] +
          '/${c.databaseSubdirectory}',
    );
  });
  tearDown(() async {
    c.dispose();
    if (c.repository.db.isOpen) await c.repository.db.close();
    await directory.delete(recursive: true);
  });

  Future<String> record({
    bool complete = false,
    int level = 1,
    String mode = 'ASSIST',
    bool pause = false,
    bool unknown = false,
    bool sound = false,
    int? date,
  }) async {
    final clock = ManualClock();
    final engine = TaskEngine(
      config: c.content.config,
      clock: clock,
      taskId: 'G1_MEMORY',
      mode: mode,
      level: level,
      song: c.content.notes,
      layoutSnapshot: {'layout_id': 'PHONE_7', 'snapshot_id': uuid()},
      seed: 47,
    );
    await c.repository.create(
      engine,
      {
        'schema_version': 1,
        'device_local_id': 'isolated-test-device',
        'device_model': 'Medium Phone',
        'clock_source': 'DART_RECEIPT',
        'sound_enabled': unknown || sound,
        'app_gain_permille': 600,
        'audio_route_category': unknown
            ? 'UNKNOWN'
            : sound
            ? c.capabilities['audio_route_category']
            : 'MUTED',
        'layout_version': 1,
      },
      null,
      'Asia/Shanghai',
    );
    if (complete) {
      for (var trial = 0; trial < 3; trial++) {
        advance(engine, clock);
        if (pause && trial == 0) {
          engine.pause('USER');
          clock.now += 1000000;
          engine.resume();
        }
        for (final key in List<int>.from(engine.expected)) {
          engine.down(1, key);
          engine.up(1);
          clock.now += 20000;
        }
        clock.now += 300000;
        engine.tick();
      }
      expect(engine.block['status'], 'COMPLETED');
    }
    engine.finish('EXITED');
    await c.repository.persist(engine);
    // Deterministic timestamps only in this isolated query-test database.
    if (date != null) {
      await c.repository.db.update(
        'sessions',
        {'started_utc_ms': date},
        where: 'session_id=?',
        whereArgs: [engine.id],
      );
      await c.repository.db.update(
        'blocks',
        {'ended_utc_ms': date + 1000},
        where: 'session_id=? AND status=\'COMPLETED\'',
        whereArgs: [engine.id],
      );
    }
    return engine.id;
  }

  testWidgets(
    'keyset pagination handles tied dates, deletion, insertion and read retry',
    (tester) async {
      for (var i = 0; i < 45; i++) {
        await record(date: i < 25 ? 1000 : 2000);
      }
      final first = await c.repository.historyPage();
      expect(first.records, hasLength(20));
      expect(first.hasMore, true);
      final duplicate = Map<String, Object?>.from(
        (await c.repository.db.query(
          'summaries',
          where: "scope='SESSION'",
          limit: 1,
        )).single,
      );
      duplicate['summary_id'] = uuid();
      duplicate['metric_version'] = 'historic-other-version';
      await c.repository.db.insert('summaries', duplicate);
      expect(await c.repository.history(), first.records);
      await c.repository.delete(first.records.first['session_id'] as String);
      final newest = await record(date: 3000);
      final second = await c.repository.historyPage(after: first.records.last);
      final third = await c.repository.historyPage(after: second.records.last);
      expect(second.records, hasLength(20));
      expect(third.records, hasLength(5));
      expect(third.hasMore, false);
      final all = [
        ...first.records,
        ...second.records,
        ...third.records,
      ].map((r) => r['session_id']).toList();
      expect(all.toSet(), hasLength(45));
      expect(all, isNot(contains(newest)));
      await c.refreshHistory();
      expect(c.history.first['session_id'], newest);
      final visible = List<Json>.from(c.history);
      await c.repository.db.close();
      await c.loadMoreHistory();
      expect(c.history, visible);
      expect(c.historyError, isNotNull);
      expect(c.historyLoading, false);
      await c.repository.open(directory.path, 'en');
      await c.loadMoreHistory();
      expect(c.history, hasLength(40));
      expect(c.historyError, isNull);
      await c.loadMoreHistory();
      expect(c.history, hasLength(45));
      expect(c.historyHasMore, false);
      await c.refreshHistory();
      final pending = c.loadMoreHistory();
      final refresh = c.refreshHistory();
      await Future.wait([pending, refresh]);
      expect(c.history, hasLength(20));
      expect(c.historyLoading, false);
    },
  );

  testWidgets(
    'trends use latest 20 completed blocks per exact condition and cascade deletion',
    (tester) async {
      final ids = <String>[];
      for (var i = 0; i < 24; i++) {
        ids.add(await record(complete: true, date: 1000 + i));
      }
      await record(complete: true, level: 2);
      await record(complete: true, mode: 'CHALLENGE');
      await record(complete: true, pause: true);
      await record(complete: true, unknown: true);
      await record(complete: true, sound: true);
      await record();
      final conditions = await c.repository.trendConditions(
        taskId: 'G1_MEMORY',
      );
      expect(conditions, hasLength(5));
      final ordinary = conditions.singleWhere((r) => r['block_count'] == 24);
      final rows = await c.repository.trendRows(
        ordinary['comparison_key'] as String,
      );
      expect(rows, hasLength(20));
      expect(rows.first['ended_utc_ms'], 2004);
      expect(rows.last['ended_utc_ms'], 2023);
      expect(
        rows.map(TrendPoint.fromRow).every((p) => p.denominator == 3),
        true,
      );
      expect(await c.repository.trendConditions(taskId: 'S1_GUIDED'), isEmpty);
      final taskGroups = await c.repository.trendTasks(taskId: 'G1_MEMORY');
      expect(taskGroups, hasLength(1));
      expect(taskGroups.single['block_count'], 29);
      final taskRows = await c.repository.trendRowsForTask('G1_MEMORY');
      expect(taskRows, hasLength(20));
      expect(
        taskRows.map(TrendPoint.fromRow).every((p) => p.denominator == 3),
        true,
      );
      expect(await c.repository.trendTasks(taskId: 'S1_GUIDED'), isEmpty);
      final sealedBefore = await c.repository.db.query('summaries');
      await c.repository.trendRows(ordinary['comparison_key'] as String);
      expect(await c.repository.db.query('summaries'), sealedBefore);
      await c.repository.delete(ids.last);
      final after = await c.repository.trendRows(
        ordinary['comparison_key'] as String,
      );
      expect(after.first['ended_utc_ms'], 2003);
      expect(after.last['ended_utc_ms'], 2022);
      await c.repository.clear();
      expect(await c.repository.trendConditions(), isEmpty);
      expect(
        await c.repository.db.rawQuery('PRAGMA foreign_key_check'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'trend UI has empty, few-point, connected, condition selection and read failure states',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Future<void> show() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TrendPage(key: UniqueKey(), c: c),
          ),
        );
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await show();
      expect(find.text('No practice trends yet'), findsOneWidget);
      await record(complete: true);
      await record(complete: true);
      await show();
      expect(find.text('A line appears with 3 valid blocks'), findsOneWidget);
      expect(
        tester.widget<TrendChart>(find.byType(TrendChart)).connectsPoints,
        false,
      );
      await record(complete: true);
      await show();
      expect(
        tester.widget<TrendChart>(find.byType(TrendChart)).connectsPoints,
        true,
      );
      await record(complete: true, level: 2);
      await show();
      await tester.tap(find.text('Choose practice'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Choose practice'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Melody memory').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TrendChart>(find.byType(TrendChart)).points,
        hasLength(4),
      );
      await c.repository.db.close();
      await show();
      expect(find.text('Retry'), findsOneWidget);
      await c.repository.open(directory.path, 'en');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(TrendChart), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
