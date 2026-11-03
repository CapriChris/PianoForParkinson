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
  static const _recordTables = {
    'dance': 'dance_sessions',
    'piece': 'piece_performances',
    'exercise': 'sessions',
  };
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
    final activePlans = (await plans())
        .where((p) => p['deleted'] != true)
        .toList();
    final progress = await automaticProgressFor([
      for (final plan in activePlans) (plan: plan, date: date),
    ]);
    final result = <Json>[];
    for (var i = 0; i < activePlans.length; i++) {
      result.add({'plan': activePlans[i], 'progress': progress[i]});
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

  /// Reads each record table once for this refresh. Results and integrity
  /// checks are shared only within the call, so edits and deletes stay visible.
  Future<List<int>> automaticProgressFor(
    List<({Json plan, DateTime date})> requests,
  ) async {
    final result = List<int>.filled(requests.length, 0);
    final daysByKind = <String, Set<String>>{};
    final due = <({int index, Json plan, String kind, String day})>[];
    for (final (index, request) in requests.indexed) {
      final (:plan, :date) = request;
      if (plan['deleted'] == true || !planDue(plan, date)) continue;
      final kind = plan['kind'] as String;
      final day = localDay(date);
      daysByKind.putIfAbsent(kind, () => {}).add(day);
      due.add((index: index, plan: plan, kind: kind, day: day));
    }

    final rowsByDay = <(String, String), List<Map<String, Object?>>>{};
    for (final entry in daysByKind.entries) {
      final days = entry.value.toList()..sort();
      final rows = await _recordsInRange(
        db,
        entry.key,
        DateTime.parse(days.first),
        _nextDay(DateTime.parse(days.last)),
        excludeLinked: false,
      );
      for (final row in rows) {
        final day = localDay(
          DateTime.fromMillisecondsSinceEpoch(row['started_utc_ms'] as int),
        );
        if (entry.value.contains(day)) {
          rowsByDay.putIfAbsent((entry.key, day), () => []).add(row);
        }
      }
    }

    final checked = Map<Map<String, Object?>, Json?>.identity();
    final totals = <(String, String, Object?, Object?), int>{};
    for (final request in due) {
      final (:index, :plan, :kind, :day) = request;
      final trainingId = kind == 'piece' ? null : plan['training_id'];
      final key = (kind, day, trainingId, plan['target_type']);
      result[index] = totals.putIfAbsent(key, () {
        var total = 0;
        for (final row in rowsByDay[(kind, day)] ?? const []) {
          if (!_matchesPlan(plan, row)) continue;
          final record = checked.putIfAbsent(
            row,
            () => _checkedRecord(kind, row),
          );
          if (record != null) total += _recordUnits(plan, record);
        }
        return total;
      });
    }
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
    final kind = p['kind'] as String;
    final rows = await _recordsInRange(
      source,
      kind,
      date,
      _nextDay(date),
      excludeLinked: excludeLinked,
    );
    final records = <Json>[];
    for (final row in rows) {
      if (!_matchesPlan(p, row)) continue;
      final record = _checkedRecord(kind, row);
      if (record != null) {
        records.add({...record, 'units': _recordUnits(p, record)});
      }
    }
    return records;
  }

  static DateTime _nextDay(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  Future<List<Map<String, Object?>>> _recordsInRange(
    DatabaseExecutor source,
    String kind,
    DateTime start,
    DateTime end, {
    required bool excludeLinked,
  }) {
    final table = _recordTables[kind]!;
    return source.rawQuery(
      'SELECT * FROM $table r WHERE profile_id=? AND started_utc_ms>=? AND started_utc_ms<? ${excludeLinked ? 'AND NOT EXISTS(SELECT 1 FROM plan_links l WHERE l.record_kind=? AND l.record_id=r.session_id)' : ''} ORDER BY started_utc_ms, session_id',
      [
        profileId,
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
        if (excludeLinked) kind,
      ],
    );
  }

  static bool _matchesPlan(Json plan, Map<String, Object?> row) {
    final kind = plan['kind'];
    return (kind != 'exercise' || row['status'] == 'COMPLETED') &&
        (kind == 'piece' ||
            plan['training_id'] == null ||
            row['task_id'] == plan['training_id']);
  }

  static Json? _checkedRecord(String kind, Map<String, Object?> row) {
    if (kind == 'exercise') {
      RecordIntegrity.session(row);
      return row;
    }
    final record = jsonDecode(row['record_json'] as String) as Json;
    if (digest(record) != row['record_hash']) {
      throw StateError('E_RECORD_INTEGRITY');
    }
    if (kind == 'dance') {
      return record['confirmed'] == true && (record['active_ms'] as int) > 0
          ? record
          : null;
    }
    PiecePerformance.validate(record);
    return row;
  }

  static int _recordUnits(Json plan, Json record) =>
      plan['kind'] == 'dance' && plan['target_type'] == 'minutes'
      ? record['active_ms'] as int
      : 1;

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
