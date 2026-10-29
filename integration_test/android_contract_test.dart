import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/platform/platform_service.dart';

void advance(TaskEngine engine, ManualClock clock) {
  for (var i = 0; i < 2500; i++) {
    clock.now += 20000;
    engine.tick();
    if (engine.phase == 'cue') engine.cuePresented();
    if (engine.phase == 'response') return;
  }
  throw StateError('No response phase');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native SoundPool, SQLite contracts and process-recovery semantics',
    (tester) async {
      final platform = PlatformService();
      await platform.activate(1);
      final content = ContentRepository();
      await content.load();
      await platform.prepare(content.soundPack);
      final caps = await platform.call('getCapabilities');
      expect(caps['audio_ready'], true);
      final first = await platform.play(0, 600),
          second = await platform.play(0, 600);
      expect(first, isNot(second));
      await platform.stop(first);
      await platform.stop(second);
      await platform.activate(2);
      final stale = await PlatformService.channel
          .invokeMapMethod<String, dynamic>('playNote', {
            'protocol_version': 1,
            'request_id': 'stale-test',
            'generation': 1,
            'note_id': 0,
            'gain_permille': 600,
          });
      expect(stale!['ok'], false);
      expect(stale['error_code'], 'E_STALE_GENERATION');
      final directory = Directory('${caps['storage_path']}/contract-${uuid()}');
      await directory.create();
      final repository = PracticeRepository();
      await repository.open(directory.path, 'en');
      final clock = ManualClock();
      final engine = TaskEngine(
        config: content.config,
        clock: clock,
        taskId: 'G1_MEMORY',
        mode: 'ASSIST',
        level: 1,
        song: content.notes,
        seed: 47,
      );
      await repository.create(
        engine,
        {'schema_version': 1, 'platform': 'ANDROID'},
        null,
        caps['timezone'] as String,
      );
      for (var block = 0; block < 2; block++) {
        for (var trial = 0; trial < 3; trial++) {
          advance(engine, clock);
          for (final key in List<int>.from(engine.expected)) {
            engine.down(1, key);
            engine.up(1);
            clock.now += 20000;
          }
          clock.now += 300000;
          engine.tick();
          await repository.persist(engine);
        }
        if (block == 0) engine.nextBlock();
      }
      await repository.persist(
        engine,
      ); // Same commit ids: retry must not duplicate decisions.
      expect(await repository.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect((await repository.detail(engine.id))!['status'], 'COMPLETED');
      final decisions = await repository.db.query(
        'adaptive_decisions',
        where: 'session_id=?',
        whereArgs: [engine.id],
      );
      expect(decisions.length, 2);
      final duplicate = Map<String, Object?>.from(
        (await repository.db.query(
          'attempts',
          where: "validity='VALID'",
          limit: 1,
        )).single,
      );
      duplicate['attempt_id'] = uuid();
      duplicate['ordinal'] = 99;
      await expectLater(
        repository.db.insert('attempts', duplicate),
        throwsA(isA<Exception>()),
      );
      final count = await repository.db.rawQuery(
        'SELECT COUNT(*) AS n FROM attempts WHERE validity=\'VALID\'',
      );
      expect(count.single['n'], 6);
      await repository.delete(engine.id);
      expect(await repository.db.query('events'), isEmpty);
      expect(await repository.db.query('blocks'), isEmpty);
      final interrupted = TaskEngine(
        config: content.config,
        clock: ManualClock(),
        taskId: 'G1_MEMORY',
        mode: 'ASSIST',
        level: 1,
        song: content.notes,
        seed: 17,
      );
      await repository.create(
        interrupted,
        {'schema_version': 1},
        null,
        caps['timezone'] as String,
      );
      advance(interrupted, interrupted.clock as ManualClock);
      await repository.persist(interrupted);
      await repository.db.close();
      final reopened = PracticeRepository();
      await reopened.open(directory.path, 'en');
      expect(
        (await reopened.detail(interrupted.id))!['status'],
        'RECOVERED_INTERRUPTED',
      );
      expect(
        (await reopened.db.query('attempts')).single['validity'],
        'INTERRUPTED',
      );
      final recovery = (await reopened.db.query(
        'events',
        where: 'kind=?',
        whereArgs: ['ERROR'],
      )).single;
      expect(recovery['offset_us'], null);
      await reopened.clear();
      expect(await reopened.db.query('profiles'), hasLength(1));
      expect(await reopened.db.query('sessions'), isEmpty);
      await reopened.db.close();
      await directory.delete(recursive: true);
      await platform.off();
    },
  );
}
