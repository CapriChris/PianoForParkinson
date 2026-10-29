import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/platform/platform_service.dart';

import 'android_contract_test.dart' show advance;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PracticeRepository repository;
  late ContentRepository content;
  late ManualClock clock;
  late TaskEngine engine;
  setUp(() async {
    final caps = await PlatformService().call('getCapabilities');
    directory = Directory('${caps['storage_path']}/stability-${uuid()}');
    await directory.create();
    repository = PracticeRepository();
    await repository.open(directory.path, 'en');
    content = ContentRepository();
    await content.load();
    clock = ManualClock();
    engine = TaskEngine(
      config: content.config,
      clock: clock,
      taskId: 'S1_GUIDED',
      mode: 'ASSIST',
      level: 1,
      song: content.notes,
      seed: 47,
    );
  });
  tearDown(() async {
    if (repository.db.isOpen) await repository.db.close();
    await directory.delete(recursive: true);
  });
  Future<void> create() => repository.create(
    engine,
    {'schema_version': 1},
    content.song,
    'Asia/Shanghai',
  );

  testWidgets('atomic creation, failed finalization and idempotent retry', (
    tester,
  ) async {
    await repository.db.execute(
      "CREATE TRIGGER fail_event BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(create(), throwsA(isA<Exception>()));
    expect(await repository.db.query('sessions'), isEmpty);
    expect(await repository.db.query('blocks'), isEmpty);
    await repository.db.execute('DROP TRIGGER fail_event');
    await create();
    for (var block = 0; block < 2; block++) {
      for (var i = 0; i < 8; i++) {
        advance(engine, clock);
        engine.down(1, engine.expected.single);
        engine.up(1);
      }
      if (block == 0) engine.nextBlock();
    }
    final commits = engine.blocks.map((b) => b['commit_id']).toList();
    await repository.db.execute(
      "CREATE TRIGGER fail_summary BEFORE INSERT ON summaries BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(repository.persist(engine), throwsA(isA<Exception>()));
    expect((await repository.detail(engine.id))!['status'], 'WAIT_ALL_UP');
    expect(await repository.db.query('adaptive_decisions'), isEmpty);
    expect(await repository.db.query('profile_task_state'), isEmpty);
    expect(await repository.db.query('attempts'), isEmpty);
    await repository.db.execute('DROP TRIGGER fail_summary');
    await repository.persist(engine);
    final first = await repository.detail(engine.id);
    clock.now += 999000;
    await repository.persist(engine);
    final repeated = await repository.detail(engine.id);
    expect(repeated, first);
    expect(engine.blocks.map((b) => b['commit_id']).toList(), commits);
    expect(await repository.db.query('adaptive_decisions'), hasLength(2));
    expect(await repository.db.query('summaries'), hasLength(3));
    expect(await repository.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    engine.events.first['payload']['tampered'] = true;
    await expectLater(
      repository.persist(engine),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          contains('E_EVENT_CONFLICT'),
        ),
      ),
    );
    expect(await repository.detail(engine.id), first);
    engine.events.first['payload'].remove('tampered');
    engine.attempts.first['result']['help_count'] = 1;
    await expectLater(
      repository.persist(engine),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'code',
          contains('E_RECORD_CONFLICT'),
        ),
      ),
    );
  });

  testWidgets(
    '200 press pairs, 100 interruptions and 5000 moves preserve records',
    (tester) async {
      await create();
      advance(engine, clock);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        engine.down(1, 1);
        engine.up(1);
        clock.now += 1000;
        if (i % 20 == 0) await repository.persist(engine);
      }
      for (var i = 0; i < 100; i++) {
        engine.pause('INTERRUPTED_BACKGROUND');
        await repository.persist(engine);
        engine.resume();
        advance(engine, clock);
      }
      engine.down(1, 1);
      for (var i = 0; i < 5000; i++) {
        clock.now += 1000;
        engine.move(1, {'x_norm': i, 'y_norm': 500000});
        if (i % 250 == 0) await repository.persist(engine);
      }
      engine.up(1);
      engine.down(2, engine.expected.single);
      engine.up(2);
      engine.finish('EXITED');
      await repository.persist(engine);
      stopwatch.stop();
      final record = (await repository.detail(engine.id))!;
      final summary = jsonDecode(record['result_json'] as String) as Json;
      expect(summary['completed'], 1);
      expect(summary['rates']['primary'], {'numerator': 0, 'denominator': 1});
      expect(summary['sample_counts']['interrupted'], 101);
      expect(
        (await repository.db.query('events')).length,
        engine.events.length,
      );
      expect(await repository.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      debugPrint(
        'STORAGE_STRESS: ${engine.events.length} events, ${stopwatch.elapsedMilliseconds} ms; virtual input, no latency assertion',
      );
      await repository.db.close();
      repository = PracticeRepository();
      await repository.open(directory.path, 'en');
      expect((await repository.detail(engine.id))!['status'], 'EXITED');
      expect(
        await repository.db.query('attempts', where: "validity='VALID'"),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'recovery rejects old engine and schema mismatch preserves data',
    (tester) async {
      await create();
      advance(engine, clock);
      await repository.persist(engine);
      await repository.db.close();
      repository = PracticeRepository();
      await repository.open(directory.path, 'en');
      final recovered = (await repository.detail(engine.id))!;
      final summary = jsonDecode(recovered['result_json'] as String) as Json;
      expect(recovered['status'], 'RECOVERED_INTERRUPTED');
      expect(summary['timings']['median_numerator_us'], isNull);
      expect(summary['quality_flags'], contains('PROCESS_DEATH'));
      await expectLater(
        repository.persist(engine),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'code',
            contains('E_TERMINAL_SESSION'),
          ),
        ),
      );
      await repository.db.update('schema_migrations', {
        'migration_checksum': '0' * 64,
      });
      await repository.db.close();
      final refused = PracticeRepository();
      await expectLater(
        refused.open(directory.path, 'en'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'code',
            contains('E_SCHEMA_VERSION'),
          ),
        ),
      );
      expect(await File('${directory.path}/practice.db').exists(), true);
    },
  );
}
