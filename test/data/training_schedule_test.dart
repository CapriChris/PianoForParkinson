import 'dart:io';

import '../domain/piece_performance_test.dart' show completedRecord;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/record_audit.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/dance_training.dart';

void main() {
  test('dance audit detects tampering', () {
    final record = {
      'session_id': 'd',
      'started_utc_ms': 1,
      'active_ms': 200,
      'covered_ms': 200,
    };
    final row = {
      'session_id': 'd',
      'started_utc_ms': 1,
      'record_json': canonical(record),
      'record_hash': digest(record),
    };
    expect(
      auditRows({
        'table': 'dance_sessions',
        'rows': [row],
      }),
      isEmpty,
    );
    expect(
      auditRows({
        'table': 'dance_sessions',
        'rows': [
          {...row, 'record_hash': 'invalid'},
        ],
      }),
      isNotEmpty,
    );
  });
  test('playback excludes seek gaps, pause and repeated coverage', () {
    final ledger = PlaybackLedger();
    ledger.observe(from: 0, to: 250, wallMs: 250, speed: 1, playing: true);
    ledger.observe(from: 250, to: 20000, wallMs: 250, speed: 1, playing: true);
    ledger.observe(from: 0, to: 250, wallMs: 250, speed: 1, playing: true);
    ledger.observe(from: 250, to: 500, wallMs: 250, speed: 1, playing: false);
    expect(ledger.activeMs, 500);
    expect(ledger.coveredMs, 250);
  });
  test('calendar uses local dates with inclusive boundaries', () {
    final p = {
      'paused': false,
      'start': '2026-10-31',
      'end': '2026-11-07',
      'days': [6],
    };
    expect(planDue(p, DateTime(2026, 10, 31)), true);
    expect(planDue(p, DateTime(2026, 11, 7)), true);
    expect(planDue(p, DateTime(2026, 11, 14)), false);
    expect(planDue({...p, 'days': []}, DateTime(2026, 11, 7)), false);
    expect(planDue({...p, 'paused': true}, DateTime(2026, 10, 31)), false);
  });
  sqfliteFfiInit();
  test(
    'expired plans turn off persistently and schedules sort from early to late',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      for (final sql in DatabaseSafety.migration4.split(';')) {
        if (sql.trim().isNotEmpty) await db.execute(sql);
      }
      final store = TrainingScheduleRepository(db, 'p');
      final base = <String, dynamic>{
        'id': 'late',
        'title': 'Plan',
        'kind': 'dance',
        'target_type': 'count',
        'target': 1,
        'start': '2026-11-02',
        'end': null,
        'days': <int>[],
        'paused': false,
        'reminder': false,
        'hour': 18,
        'minute': 0,
      };
      await store.savePlan(base);
      await store.savePlan({...base, 'id': 'early', 'hour': 9, 'minute': 30});
      await store.savePlan({
        ...base,
        'id': 'paused-current',
        'hour': 8,
        'paused': true,
      });
      await store.savePlan({
        ...base,
        'id': 'future',
        'start': '2026-11-03',
        'hour': 8,
      });
      await store.savePlan({
        ...base,
        'id': 'expired-once',
        'start': '2026-11-01',
        'end': '2026-12-30',
      });
      await store.savePlan({
        ...base,
        'id': 'expired-repeat',
        'start': '2026-10-01',
        'end': '2026-11-01',
        'days': [1, 2],
      });
      await store.savePlan({
        ...base,
        'id': 'ends-today',
        'start': '2026-10-01',
        'end': '2026-11-02',
        'days': [1, 2],
      });
      await store.savePlan({
        ...base,
        'id': 'unlimited',
        'start': '2026-10-01',
        'days': [1, 2],
      });
      await TrainingScheduleRepository(
        db,
        'q',
      ).savePlan({...base, 'id': 'other-profile', 'start': '2026-11-01'});
      final day = DateTime(2026, 11, 2);
      await store.disableExpiredPlans(day);
      await store.disableExpiredPlans(day);
      final plans = {for (final plan in await store.plans()) plan['id']: plan};
      expect(plans['expired-once']!['paused'], isTrue);
      expect(plans['expired-repeat']!['paused'], isTrue);
      expect(plans['paused-current']!['paused'], isTrue);
      for (final id in ['late', 'early', 'future', 'ends-today', 'unlimited']) {
        expect(plans[id]!['paused'], isFalse);
      }
      expect(
        (await TrainingScheduleRepository(db, 'q').plans()).single['paused'],
        isFalse,
      );
      final order = (await store.summaries(day))
          .map((r) => r['plan']['id'])
          .toList();
      expect(order, [
        'ends-today',
        'unlimited',
        'paused-current',
        'early',
        'late',
        'future',
        'expired-repeat',
        'expired-once',
      ]);
    },
  );
  test('automatic progress uses saved completed records, dates and profiles without duplicate counting', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      for (final sql in DatabaseSafety.migration4.split(';')) {
        if (sql.trim().isNotEmpty) await db.execute(sql);
      }
      final store = TrainingScheduleRepository(db, 'p');
      final other = TrainingScheduleRepository(db, 'q');
      final day = DateTime(2026, 11, 1, 12);
      final plan = <String, dynamic>{
        'id': 'count',
        'title': 'Dance',
        'kind': 'dance',
        'target_type': 'count',
        'target': 2,
        'start': localDay(day),
        'end': null,
        'days': [],
        'paused': false,
      };
      await store.savePlan(plan);
      await store.savePlan({...plan, 'id': 'also-count'});
      await store.savePlan({
        ...plan,
        'id': 'minutes',
        'target_type': 'minutes',
      });
      await store.savePlan({...plan, 'id': 'paused', 'paused': true});
      await store.savePlan({...plan, 'id': 'tomorrow', 'start': '2026-11-02'});
      await other.savePlan({...plan, 'id': 'other-profile'});
      final record = <String, dynamic>{
        'session_id': 'first',
        'started_utc_ms': day.millisecondsSinceEpoch,
        'active_ms': 30000,
        'covered_ms': 30000,
        'confirmed': true,
      };
      await store.saveDance(record);
      await store.saveDance(record); // Save retry must not add another session.
      await store.saveDance({
        ...record,
        'session_id': 'unfinished',
        'confirmed': false,
      });
      await store.saveDance({
        ...record,
        'session_id': 'yesterday',
        'started_utc_ms': day
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });
      await other.saveDance({...record, 'session_id': 'someone-else'});
      final previousDay = DateTime(day.year, day.month, day.day - 1);
      final recurring = {
        ...plan,
        'start': localDay(previousDay),
        'days': [previousDay.weekday, day.weekday],
      };
      final requests = [
        (plan: recurring, date: previousDay),
        (plan: recurring, date: day),
        (plan: {...recurring, 'target_type': 'minutes'}, date: day),
        (plan: {...recurring, 'training_id': 'different'}, date: day),
        (plan: {...recurring, 'paused': true}, date: day),
      ];
      expect(await store.automaticProgressFor(requests), [1, 1, 30000, 0, 0]);
      for (var refresh = 0; refresh < 2; refresh++) {
        final summaries = await store.summaries(day);
        expect(summaries.length, 5); // Include disabled and future plans.
        final values = {
          for (final s in summaries) s['plan']['id']: s['progress'],
        };
        expect(values, {
          'count': 1,
          'also-count': 1,
          'minutes': 30000,
          'paused': 0,
          'tomorrow': 0,
        });
      }
      final occurrence = (await store.occurrences(day)).first;
      await store.link(
        occurrence,
        'first',
      ); // Old links do not hide or add records.
      expect(await store.automaticProgress(plan, day), 1);
      await store.saveDance({...record, 'session_id': 'second'});
      expect(await store.automaticProgressFor(requests), [1, 2, 60000, 0, 0]);
      expect(await store.automaticProgress(plan, day), 2);
      expect(
        await store.automaticProgress({...plan, 'target_type': 'minutes'}, day),
        60000,
      );
      await store.deleteDance('second');
      expect(await store.automaticProgressFor(requests), [1, 1, 30000, 0, 0]);
      expect(await store.automaticProgress(plan, day), 1);
      await store.deletePlans(['count', 'also-count', 'other-profile']);
      expect((await store.summaries(day)).length, 3);
      expect((await other.summaries(day)).length, 1);
      expect(
        (await store.dances()).length,
        3,
      ); // Deletion keeps training history.
    } finally {
      await db.close();
    }
  });
  test(
    'piano piece plans count all pieces including legacy specific-piece plans',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        for (final sql
            in '${DatabaseSafety.migration3};${DatabaseSafety.migration4}'
                .split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
        final record = completedRecord();
        await db.insert('piece_performances', {
          for (final field in [
            'session_id',
            'content_id',
            'started_utc_ms',
            'ended_utc_ms',
            'session_utc_offset_minutes',
          ])
            field: record[field],
          'profile_id': 'p',
          'record_json': canonical(record),
          'record_hash': digest(record),
        });
        final day = DateTime.fromMillisecondsSinceEpoch(
          record['started_utc_ms'] as int,
        );
        final plan = <String, dynamic>{
          'kind': 'piece',
          'start': localDay(day),
          'end': null,
          'days': [],
          'paused': false,
          'target_type': 'count',
        };
        final store = TrainingScheduleRepository(db, 'p');
        expect(
          await store.automaticProgress({
            ...plan,
            'training_id': record['content_id'],
          }, day),
          1,
        );
        expect(
          await store.automaticProgress({
            ...plan,
            'training_id': 'another-piece',
          }, day),
          1,
        );
        expect(await store.automaticProgress(plan, day), 1);
      } finally {
        await db.close();
      }
    },
  );
  for (final oldVersion in [1, 2, 3]) {
    test('schema $oldVersion upgrades to 4 without losing profile', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      try {
        final schema = File('assets/config/schema.sql')
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('--'))
            .join('\n');
        for (final sql in schema.split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
        await db.insert('profiles', {
          'profile_id': 'p',
          'created_utc_ms': 0,
          'locale': 'zh-Hans',
          'mode': 'ASSIST',
          'settings_json': '{}',
        });
        await db.insert('schema_migrations', {
          'version': 1,
          'applied_utc_ms': 0,
          'migration_checksum': digest(schema),
        });
        if (oldVersion > 1) await DatabaseSafety.migrate(db, 1, oldVersion);
        await DatabaseSafety.migrate(db, oldVersion, 4);
        await DatabaseSafety.verify(db);
        expect((await db.query('profiles')).single['profile_id'], 'p');
        final store = TrainingScheduleRepository(db, 'p');
        final day = DateTime.now();
        final plan = <String, dynamic>{
          'id': 'one',
          'title': 'Dance',
          'kind': 'dance',
          'target_type': 'count',
          'target': 1,
          'start': localDay(day),
          'end': null,
          'days': [],
          'paused': false,
        };
        await store.savePlan(plan);
        final occurrence = (await store.occurrences(day)).single;
        expect((await store.occurrences(day)).length, 1);
        final record = <String, dynamic>{
          'session_id': 'dance-1',
          'started_utc_ms': day.millisecondsSinceEpoch,
          'active_ms': 1000,
          'covered_ms': 1000,
          'confirmed': true,
        };
        await store.saveDance(record);
        await store.saveDance(record);
        expect((await store.dances()).length, 1);
        expect((await store.occurrences(day)).single['progress'], 1);
        await store.link(occurrence, 'dance-1');
        expect((await store.occurrences(day)).single['progress'], 1);
        await expectLater(store.link(occurrence, 'dance-1'), throwsStateError);
        await store.savePlan({...plan, 'target': 2});
        expect((await store.occurrences(day)).single['plan']['target'], 1);
        await expectLater(
          store.saveDance({...record, 'confirmed': false}),
          throwsStateError,
        );
        expect(digest(record), isNotEmpty);
        await store.deleteDance('dance-1');
        expect((await store.occurrences(day)).single['progress'], 0);
        await store.deletePlan('one');
        expect(await store.occurrences(day), isEmpty);
      } finally {
        await db.close();
      }
    });
  }
}
