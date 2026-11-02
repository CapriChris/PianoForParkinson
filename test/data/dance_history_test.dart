import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';

import '../domain/piece_performance_test.dart' show completedRecord;

void main() {
  sqfliteFfiInit();
  test('dance and piano share stable history pagination, profile filtering and integrity checks', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final schema = File('assets/config/schema.sql')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
    for (final sql
        in '$schema;${DatabaseSafety.migration3};${DatabaseSafety.migration4}'
            .split(';')) {
      if (sql.trim().isNotEmpty && !sql.trim().startsWith('PRAGMA')) {
        await db.execute(sql);
      }
    }
    final repository = PracticeRepository()
      ..db = db
      ..profile = {'profile_id': 'p'};
    final store = TrainingScheduleRepository(db, 'p');
    final expected = <Json>[];
    final base = DateTime.utc(2026, 11, 2, 4).millisecondsSinceEpoch;
    for (var i = 0; i < 35; i++) {
      final record = <String, dynamic>{
        'session_id': 'dance-${i.toString().padLeft(2, '0')}',
        'title': '新平衡舞步六式',
        'content_id': 'hkpdf-balance-six',
        'started_utc_ms': base + i ~/ 2 * 1000,
        'utc_offset_minutes': 480,
        'active_ms': 2000,
        'covered_ms': 2000,
        'confirmed': true,
      };
      await store.saveDance(record);
      expected.add(record);
    }
    for (var i = 0; i < 2; i++) {
      final record = {
        ...completedRecord(),
        'session_id': 'piece-$i',
        'started_utc_ms': base + (10 + i) * 1000,
        'ended_utc_ms': base + (10 + i) * 1000 + 32000,
      };
      await repository.savePiecePerformance(record);
      expected.add(record);
    }
    await TrainingScheduleRepository(db, 'q').saveDance({
      ...expected.first,
      'session_id': 'other-profile',
      'started_utc_ms': base + 999999,
    });
    expected.sort((a, b) {
      final time = (b['started_utc_ms'] as int).compareTo(
        a['started_utc_ms'] as int,
      );
      return time != 0
          ? time
          : (a['session_id'] as String).compareTo(b['session_id'] as String);
    });
    final first = await repository.historyPage();
    expect(first.records.length, 20);
    expect(first.hasMore, isTrue);
    final second = await repository.historyPage(after: first.records.last);
    expect(second.hasMore, isFalse);
    expect(
      [...first.records, ...second.records].map((r) => r['session_id']),
      expected.map((r) => r['session_id']),
    );
    final dance = (await repository.detail('dance-00'))!;
    expect(dance['task_id'], 'DANCE');
    expect(
      recordDateLabel(recordedDate(dance, 'started_utc_ms')),
      '2026-11-02 12:00',
    );
    expect(await repository.detail('other-profile'), isNull);
    await db.update(
      'dance_sessions',
      {'record_hash': 'tampered'},
      where: 'session_id=?',
      whereArgs: ['dance-00'],
    );
    expect(
      (await repository.detail('dance-00'))!['record_unavailable'],
      isTrue,
    );
    expect(
      (await repository.detail('dance-01'))!['record_unavailable'],
      isNull,
    );
    await store.deleteDance('dance-34');
    expect(await repository.detail('dance-34'), isNull);
    expect(
      (await repository.historyPage()).records.any(
        (r) => r['session_id'] == 'dance-34',
      ),
      isFalse,
    );
  });
}
