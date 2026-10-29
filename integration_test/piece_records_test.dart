import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/data/record_audit.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/platform/platform_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'isolated SQLite v2 migration, piece history, idempotency and audit',
    (tester) async {
      final caps = await PlatformService().call('getCapabilities');
      final directory = Directory(
        '${caps['storage_path']}/piece-record-test-${uuid()}',
      );
      await directory.create();
      var repo = PracticeRepository();
      try {
        await repo.open(directory.path, 'zh-Hans');
        final content = ContentRepository();
        await content.load();
        final engine = TaskEngine(
          config: content.config,
          clock: ManualClock(),
          taskId: 'G1_MEMORY',
          mode: 'ASSIST',
          level: 1,
          layoutSnapshot: {'layout_id': 'COMPACT'},
          song: content.notes,
          seed: 19,
        );
        await repo.create(
          engine,
          {
            'schema_version': 1,
            'platform': 'ANDROID',
            'os_version': '${caps['os_version']}',
            'app_version': appVersion,
            'build_id': appBuild,
            'device_model': '${caps['device_model']}',
            'device_local_id': 'isolated-piece-test',
            'clock_source': 'DART_RECEIPT',
            'layout_id': 'COMPACT',
            'audio_backend': 'ANDROID_SOUNDPOOL',
            'audio_route_category': 'MUTED',
            'sound_enabled': false,
            'screen_reader_active': false,
            'app_gain_permille': 600,
            'window_width_dp': 411,
            'window_height_dp': 914,
            'text_scale_permille': 1000,
          },
          null,
          caps['timezone'] as String,
        );
        engine.finish('EXITED');
        await repo.persist(engine);
        final old = await repo.detail(engine.id);
        final profile = canonical((await repo.db.query('profiles')).single);
        // Construct an exact v2 fixture in this temporary database only.
        await repo.db.execute('DROP TABLE piece_performances');
        await repo.db.delete('schema_migrations', where: 'version=3');
        await repo.db.setVersion(2);
        await repo.db.close();
        repo = PracticeRepository();
        await repo.open(directory.path, 'zh-Hans');
        expect(await repo.db.getVersion(), 3);
        expect(await repo.detail(engine.id), old);
        expect(canonical((await repo.db.query('profiles')).single), profile);
        Json? first;
        for (var i = 0; i < 24; i++) {
          final clock = ManualClock();
          final player = ScrollingPiecePlayer(
            content.pieces.first,
            clock,
            tempo: 80,
          )..start();
          clock.now = player.atTick(8);
          player.down(1, 2);
          player.up(1);
          clock.now = player.atTick(8) + player.totalUs;
          player.tick();
          final r = PiecePerformance.completed(player, DateTime.now());
          // Force timestamp ties so the mixed cursor has to use IDs as well.
          r['started_utc_ms'] = 1800000000000;
          r['ended_utc_ms'] = 1800000030000;
          first ??= r;
          await repo.savePiecePerformance(r);
          await repo.savePiecePerformance(r);
        }
        expect(await repo.db.query('piece_performances'), hasLength(24));
        expect(await repo.db.query('sessions'), hasLength(1));
        final page1 = await repo.historyPage();
        final page2 = await repo.historyPage(after: page1.records.last);
        final all = [...page1.records, ...page2.records];
        expect(all, hasLength(25));
        expect(all.map((r) => r['session_id']).toSet(), hasLength(25));
        expect(page1.hasMore, isTrue);
        expect(page2.hasMore, isFalse);
        expect(all.where((r) => r['record_unavailable'] == true), isEmpty);
        final id = first!['session_id'] as String;
        expect(
          jsonDecode((await repo.detail(id))!['result_json'] as String),
          first,
        );
        await repo.db.close();
        repo = PracticeRepository();
        await repo.open(directory.path, 'zh-Hans');
        expect(
          (await repo.historyPage()).records.first['task_id'],
          'PIANO_PIECE',
        );
        final audit = await RecordAudit.run(repo.safety);
        expect(audit['complete'], isTrue);
        expect(audit['issues'], 0, reason: canonical(audit));
        await expectLater(
          repo.savePiecePerformance({...first, 'wrong_presses': 9}),
          throwsStateError,
        );
        await repo.db.update(
          'piece_performances',
          {'record_hash': '0' * 64},
          where: 'session_id=?',
          whereArgs: [id],
        );
        expect((await repo.detail(id))!['record_unavailable'], isTrue);
        await repo.delete(id);
        expect(await repo.detail(id), isNull);
        expect(await repo.detail(engine.id), old);
      } finally {
        if (repo.db.isOpen) await repo.db.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
