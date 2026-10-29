import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'M2 two blocks: engine, SQLite, sealed gap metrics, history and trend',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'dual-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      final root = c.capabilities['storage_path'] as String,
          path = '${c.capabilities['storage_path']}/${c.databaseSubdirectory}';
      addTearDown(() async {
        c.dispose();
        if (c.repository.db.isOpen) await c.repository.db.close();
        final dir = Directory(path).absolute;
        if (!dir.path.startsWith(
              '${Directory(root).absolute.path}${Platform.pathSeparator}',
            ) ||
            !dir.path.endsWith(c.databaseSubdirectory!)) {
          throw StateError('Unsafe cleanup');
        }
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      await c.updateSettings(locale: 'en', onboard: true);
      final clock = ManualClock();
      final e = TaskEngine(
        config: c.content.config,
        clock: clock,
        taskId: 'M2_DUAL_ZONE',
        mode: 'ASSIST',
        level: 1,
        song: [],
        seed: 47,
        layoutSnapshot: {
          'layout_id': 'DUAL_ZONE_SIX_KEYS',
          'snapshot_id': 'isolated-synthetic-layout',
        },
      );
      // Synthetic input verifies scoring/storage; no claim of hardware touch verification.
      await c.repository.create(
        e,
        {
          'schema_version': 1,
          'device_local_id': 'synthetic-m2',
          'device_model': 'emulator',
          'clock_source': 'DART_RECEIPT',
          'sound_enabled': false,
          'app_gain_permille': 0,
          'audio_route_category': 'MUTED',
          'layout_version': 1,
        },
        null,
        'Asia/Shanghai',
      );
      for (var block = 0; block < 2; block++) {
        for (var i = 0; i < 12; i++) {
          for (var t = 0; t < 2500 && e.phase != 'response'; t++) {
            clock.now += 20000;
            e.tick();
            if (e.phase == 'cue') e.cuePresented();
          }
          expect(e.phase, 'response');
          e.down(1, e.expected[0]);
          clock.now += i == 0 ? 1000001 : 200000;
          e.down(2, e.expected[1]);
          clock.now += e.responseRemainingUs!;
          e.tick();
          e.up(1);
          e.up(2);
        }
        await c.repository.persist(e);
        if (block == 0) e.nextBlock();
      }
      expect(e.ended, true);
      expect(e.summary()['rates']['primary']['numerator'], 22);
      expect(e.summary()['timing_groups']['dual_gap']['samples'], 24);
      await c.repository.persist(e);
      final record = await c.repository.detail(e.id);
      expect(record!['status'], 'COMPLETED');
      expect((await c.repository.historyPage()).records, hasLength(1));
      final conditions = await c.repository.trendConditions(
        taskId: 'M2_DUAL_ZONE',
      );
      expect(conditions, hasLength(1));
      expect(
        await c.repository.trendRows(conditions.single['comparison_key']),
        hasLength(2),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ResultPage(c: c, record: record),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
      final title = find.text('Practice details');
      await tester.scrollUntilVisible(
        title,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(find.text('Two-zone hits'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('Two-zone response gap:'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await c.repository.delete(e.id);
      expect(
        await c.repository.trendConditions(taskId: 'M2_DUAL_ZONE'),
        isEmpty,
      );
    },
  );
}
