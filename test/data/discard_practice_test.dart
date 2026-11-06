import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/task_engine_test.dart' show ready, play;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late PracticeRepository repository;
  late TaskEngine engine;
  late ManualClock clock;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('piano-discard-');
    repository = PracticeRepository();
    await repository.open(directory.path, 'en');
    final content = ContentRepository();
    await content.load();
    clock = ManualClock();
    engine = TaskEngine(
      config: content.config,
      clock: clock,
      taskId: 'G1_MEMORY',
      mode: 'ASSIST',
      level: 1,
      song: content.notes,
      seed: 1,
    );
  });
  tearDown(() async {
    await repository.db.close();
    await directory.delete(recursive: true);
  });

  Future<void> create() => repository.create(
    engine,
    {
      'schema_version': 1,
      'platform': 'ANDROID',
      'os_version': 'test',
      'app_version': 'test',
      'build_id': 'test',
      'device_model': 'test',
      'device_local_id': 'test',
      'clock_source': 'DART_RECEIPT',
      'layout_id': 'test',
      'audio_backend': 'SOUNDPOOL',
      'audio_route_category': 'MUTED',
      'sound_enabled': false,
      'screen_reader_active': false,
      'app_gain_permille': 600,
      'window_width_dp': 800,
      'window_height_dp': 360,
      'text_scale_permille': 1000,
    },
    null,
    'Asia/Shanghai',
  );

  for (final hasPreviousLevel in [true, false]) {
    test(
      'discard removes partial records and restores level ($hasPreviousLevel)',
      () async {
        final original = <String, Object?>{
          'profile_id': repository.profile['profile_id'],
          'task_id': engine.taskId,
          'mode': engine.mode,
          'parameter_profile_version': engine.config.json['version'],
          'level': 2,
          'updated_utc_ms': 123,
        };
        if (hasPreviousLevel) {
          await repository.db.insert('profile_task_state', original);
        }
        await create();
        ready(engine, clock);
        play(engine, clock, List<int>.from(engine.expected));
        engine.pause('USER');
        await repository.persist(engine);
        expect(await repository.db.query('attempts'), isNotEmpty);
        // Simulate a difficulty change committed earlier in this same session.
        await repository.db.insert('profile_task_state', {
          ...original,
          'level': 3,
          'updated_utc_ms': 456,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await repository.discard(engine.id);
        for (final table in [
          'sessions',
          'blocks',
          'trials',
          'attempts',
          'events',
          'adaptive_decisions',
          'summaries',
          'plan_links',
        ]) {
          expect(await repository.db.query(table), isEmpty, reason: table);
        }
        expect(
          await repository.db.query('profile_task_state'),
          hasPreviousLevel ? [original] : isEmpty,
        );
        expect(
          await repository.db.rawQuery('PRAGMA foreign_key_check'),
          isEmpty,
        );
      },
    );
  }

  test('failed discard rolls back and can be retried', () async {
    await create();
    final before = await repository.detail(engine.id);
    await repository.db.execute(
      "CREATE TRIGGER refuse_discard BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await expectLater(repository.discard(engine.id), throwsA(isA<Exception>()));
    expect(await repository.detail(engine.id), before);
    await repository.db.execute('DROP TRIGGER refuse_discard');
    await repository.discard(engine.id);
    expect(await repository.detail(engine.id), isNull);
  });

  test(
    'background open never finalizes an interrupted active training',
    () async {
      await create();
      final before = await repository.detail(engine.id);
      await repository.db.close();
      final background = PracticeRepository();
      await background.open(directory.path, 'en', recoverInterrupted: false);
      expect(await background.detail(engine.id), before);
      await background.db.close();
      // Normal interactive startup still performs the original recovery.
      await repository.open(directory.path, 'en');
      expect(
        (await repository.detail(engine.id))!['status'],
        'RECOVERED_INTERRUPTED',
      );
    },
  );

  test('saved sessions cannot be discarded as active training', () async {
    await create();
    engine.finish('EXITED');
    await repository.persist(engine);
    await expectLater(repository.discard(engine.id), throwsStateError);
    expect((await repository.detail(engine.id))!['status'], 'EXITED');
  });
}
