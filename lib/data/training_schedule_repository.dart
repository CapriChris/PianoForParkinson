import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../domain/piece_performance.dart';
import 'record_integrity.dart';

class TrainingScheduleRepository {
  TrainingScheduleRepository(this.db, this.profileId);
  final Database db;
  final String profileId;
  Future<List<Json>> plans() async => (await db.query(
    'training_plans',
    where: 'profile_id=?',
    whereArgs: [profileId],
  )).map((r) => jsonDecode(r['plan_json'] as String) as Json).toList();
  Future<void> savePlan(Json plan) async {
    if ((plan['title'] as String).trim().isEmpty ||
        !['dance', 'piece', 'exercise'].contains(plan['kind']) ||
        !['count', 'minutes'].contains(plan['target_type']) ||
        (plan['target'] as int) < 1 ||
        (plan['target_type'] == 'minutes' && plan['kind'] != 'dance') ||
        (plan['end'] != null &&
            (plan['end'] as String).compareTo(plan['start'] as String) < 0)) {
      throw const FormatException('Invalid plan');
    }
    await db.transaction((tx) async {
      final old = await tx.query(
        'training_plans',
        where: 'plan_id=?',
        whereArgs: [plan['id']],
      );
      if (old.isNotEmpty && old.single['profile_id'] != profileId) {
        throw StateError('E_PROFILE');
      }
      if (old.isEmpty) {
        await tx.insert('training_plans', {
          'plan_id': plan['id'],
          'profile_id': profileId,
          'plan_json': canonical(plan),
        });
      } else {
        await tx.update(
          'training_plans',
          {'plan_json': canonical(plan)},
          where: 'plan_id=? AND profile_id=?',
          whereArgs: [plan['id'], profileId],
        );
      }
      // Historical and linked occurrences retain their original snapshot.
      await tx.rawDelete(
        'DELETE FROM plan_occurrences WHERE plan_id=? AND local_date>=? AND skipped=0 AND NOT EXISTS(SELECT 1 FROM plan_links l WHERE l.occurrence_id=plan_occurrences.occurrence_id)',
        [plan['id'], localDay(DateTime.now())],
      );
    });
  }

  Future<void> deletePlan(String id) => deletePlans([id]);

  Future<void> deletePlans(Iterable<String> ids) => db.transaction((tx) async {
    for (final id in ids.toSet()) {
      await _deletePlan(tx, id);
    }
  });

  Future<void> _deletePlan(Transaction tx, String id) async {
    final rows = await tx.query(
      'training_plans',
      where: 'plan_id=? AND profile_id=?',
      whereArgs: [id, profileId],
    );
    if (rows.isEmpty) return;
    final p = jsonDecode(rows.single['plan_json'] as String) as Json;
    await tx.rawDelete(
      'DELETE FROM plan_occurrences WHERE plan_id=? AND local_date>=? AND skipped=0 AND NOT EXISTS(SELECT 1 FROM plan_links l WHERE l.occurrence_id=plan_occurrences.occurrence_id)',
      [id, localDay(DateTime.now())],
    );
    p['paused'] = true;
    p['deleted'] = true;
    await tx.update(
      'training_plans',
      {'plan_json': canonical(p)},
      where: 'plan_id=?',
      whereArgs: [id],
    );
  }

  // Each plan measures its own scheduled day's saved training. A record is
  // counted once per plan, regardless of refreshes or legacy manual links.
  Future<int> automaticProgress(
    Json plan,
    DateTime date, {
    DatabaseExecutor? executor,
  }) async {
    if (plan['deleted'] == true || !planDue(plan, date)) return 0;
    final records = await candidates(
      {'plan': plan, 'local_date': localDay(date)},
      executor: executor,
      excludeLinked: false,
    );
    return records.fold<int>(0, (sum, r) => sum + (r['units'] as int));
  }

  Future<List<Json>> summaries(DateTime date) async {
    final result = <Json>[];
    for (final plan in await plans()) {
      if (plan['deleted'] == true) continue;
      result.add({
        'plan': plan,
        'progress': await automaticProgress(plan, date),
      });
    }
    result.sort((a, b) {
      final first = a['plan'] as Json, second = b['plan'] as Json;
      final firstEnded = planExpired(first, date);
      final secondEnded = planExpired(second, date);
      if (firstEnded != secondEnded) return firstEnded ? 1 : -1;
      return comparePlanSchedule(first, second);
    });
    return result;
  }

  Future<void> disableExpiredPlans(DateTime date) => db.transaction((tx) async {
    final rows = await tx.query(
      'training_plans',
      where: 'profile_id=?',
      whereArgs: [profileId],
    );
    for (final row in rows) {
      final plan = jsonDecode(row['plan_json'] as String) as Json;
      if (plan['deleted'] != true &&
          plan['paused'] != true &&
          planExpired(plan, date)) {
        await tx.update(
          'training_plans',
          {
            'plan_json': canonical({...plan, 'paused': true}),
          },
          where: 'plan_id=? AND profile_id=?',
          whereArgs: [row['plan_id'], profileId],
        );
      }
    }
  });

  Future<List<Json>> occurrences(DateTime date) async {
    final day = localDay(date);
    return db.transaction((tx) async {
      final rows = await tx.query(
        'training_plans',
        where: 'profile_id=?',
        whereArgs: [profileId],
      );
      final result = <Json>[];
      for (final row in rows) {
        final p = jsonDecode(row['plan_json'] as String) as Json;
        final id = '${p['id']}:$day';
        var existing = await tx.query(
          'plan_occurrences',
          where: 'occurrence_id=?',
          whereArgs: [id],
        );
        if (existing.isEmpty && p['deleted'] != true && planDue(p, date)) {
          await tx.insert('plan_occurrences', {
            'occurrence_id': id,
            'plan_id': p['id'],
            'local_date': day,
            'snapshot_json': canonical(p),
          });
          existing = await tx.query(
            'plan_occurrences',
            where: 'occurrence_id=?',
            whereArgs: [id],
          );
        }
        if (existing.isNotEmpty) {
          final snapshot =
              jsonDecode(existing.single['snapshot_json'] as String) as Json;
          final progress = await automaticProgress(
            snapshot,
            date,
            executor: tx,
          );
          result.add({
            ...existing.single,
            'plan': jsonDecode(existing.single['snapshot_json'] as String),
            'progress': progress,
            'skipped': 0,
          });
        }
      }
      return result;
    });
  }

  Future<void> skip(String occurrence, bool value) async {
    await db.rawUpdate(
      'UPDATE plan_occurrences SET skipped=? WHERE occurrence_id=? AND plan_id IN (SELECT plan_id FROM training_plans WHERE profile_id=?)',
      [value ? 1 : 0, occurrence, profileId],
    );
  }

  Future<void> saveDance(Json record) async {
    if (record['active_ms'] is! int ||
        record['active_ms'] < 0 ||
        record['covered_ms'] is! int ||
        record['covered_ms'] < 0) {
      throw const FormatException('Invalid playback record');
    }
    await db.transaction((tx) async {
      final old = await tx.query(
        'dance_sessions',
        where: 'session_id=?',
        whereArgs: [record['session_id']],
      );
      if (old.isNotEmpty) {
        if (old.single['record_hash'] != digest(record) ||
            old.single['profile_id'] != profileId) {
          throw StateError('E_RECORD_CONFLICT');
        }
        return;
      }
      await tx.insert('dance_sessions', {
        'session_id': record['session_id'],
        'profile_id': profileId,
        'started_utc_ms': record['started_utc_ms'],
        'record_json': canonical(record),
        'record_hash': digest(record),
      });
    });
  }

  Future<void> deleteDance(String id) async => db.transaction((tx) async {
    final rows = await tx.query(
      'dance_sessions',
      where: 'session_id=? AND profile_id=?',
      whereArgs: [id, profileId],
    );
    if (rows.isEmpty) return;
    await tx.delete(
      'plan_links',
      where: 'record_kind=? AND record_id=?',
      whereArgs: ['dance', id],
    );
    await tx.delete(
      'dance_sessions',
      where: 'session_id=? AND profile_id=?',
      whereArgs: [id, profileId],
    );
  });
  Future<List<Json>> dances() async =>
      (await db.query(
        'dance_sessions',
        where: 'profile_id=?',
        whereArgs: [profileId],
        orderBy: 'started_utc_ms DESC',
        limit: 100,
      )).map((r) {
        final record = jsonDecode(r['record_json'] as String) as Json;
        if (digest(record) != r['record_hash']) {
          throw StateError('E_RECORD_INTEGRITY');
        }
        return record;
      }).toList();
  Future<List<Json>> candidates(
    Json occurrence, {
    DatabaseExecutor? executor,
    bool excludeLinked = true,
  }) async {
    final source = executor ?? db;
    final p = occurrence['plan'] as Json;
    final date = DateTime.parse(occurrence['local_date'] as String);
    final start = date.millisecondsSinceEpoch,
        end = DateTime(
          date.year,
          date.month,
          date.day + 1,
        ).millisecondsSinceEpoch;
    final kind = p['kind'] as String;
    final table = {
      'dance': 'dance_sessions',
      'piece': 'piece_performances',
      'exercise': 'sessions',
    }[kind]!;
    final rows = await source.rawQuery(
      'SELECT * FROM $table r WHERE profile_id=? AND started_utc_ms>=? AND started_utc_ms<? ${excludeLinked ? 'AND NOT EXISTS(SELECT 1 FROM plan_links l WHERE l.record_kind=? AND l.record_id=r.session_id)' : ''} ORDER BY started_utc_ms, session_id',
      [profileId, start, end, if (excludeLinked) kind],
    );
    return rows
        .where(
          (r) =>
              (kind != 'exercise' || r['status'] == 'COMPLETED') &&
              (kind == 'piece' ||
                  p['training_id'] == null ||
                  r[kind == 'piece' ? 'content_id' : 'task_id'] ==
                      p['training_id']),
        )
        .map((r) {
          if (kind == 'dance') {
            final d = jsonDecode(r['record_json'] as String) as Json;
            if (digest(d) != r['record_hash']) {
              throw StateError('E_RECORD_INTEGRITY');
            }
            return {
              ...d,
              'units': d['confirmed'] != true || (d['active_ms'] as int) <= 0
                  ? 0
                  : p['target_type'] == 'minutes'
                  ? d['active_ms']
                  : d['confirmed'] == true
                  ? 1
                  : 0,
            };
          }
          if (kind == 'piece') {
            final value = jsonDecode(r['record_json'] as String) as Json;
            if (digest(value) != r['record_hash']) {
              throw StateError('E_RECORD_INTEGRITY');
            }
            PiecePerformance.validate(value);
          } else {
            RecordIntegrity.session(Map<String, dynamic>.from(r));
          }
          return {...r, 'units': 1};
        })
        .where((r) => (r['units'] as int) > 0)
        .toList();
  }

  Future<void> link(Json occurrence, String recordId) async =>
      db.transaction((tx) async {
        // Re-read eligible records and authoritative snapshot before insertion.
        final rows = await tx.rawQuery(
          'SELECT o.* FROM plan_occurrences o JOIN training_plans p ON p.plan_id=o.plan_id WHERE o.occurrence_id=? AND p.profile_id=?',
          [occurrence['occurrence_id'], profileId],
        );
        if (rows.isEmpty) throw StateError('E_OCCURRENCE');
        final current = {
          ...rows.single,
          'plan': jsonDecode(rows.single['snapshot_json'] as String),
        };
        final eligible = await candidates(current, executor: tx);
        final record = eligible
            .where((r) => r['session_id'] == recordId)
            .firstOrNull;
        if (record == null) throw StateError('E_RECORD_NOT_ELIGIBLE');
        await tx.insert('plan_links', {
          'occurrence_id': current['occurrence_id'],
          'record_kind': current['plan']['kind'],
          'record_id': recordId,
          'units': record['units'],
        });
        await tx.update(
          'plan_occurrences',
          {'skipped': 0},
          where: 'occurrence_id=?',
          whereArgs: [current['occurrence_id']],
        );
      });
}
