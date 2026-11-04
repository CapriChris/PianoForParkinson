/// Preserve local v4 data and upload validated, versioned immutable snapshots.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../data/practice_repository.dart';
import '../data/training_schedule_repository.dart';
import '../domain/dance_training.dart' show localDay, planDue;
import 'remote_api.dart';
import 'sync_store.dart';

class SyncOutcome {
  const SyncOutcome(this.uploaded, this.skipped, this.errors);
  final int uploaded;
  final int skipped;
  final List<String> errors;
}

class CrossClientSync {
  CrossClientSync(
    this.repository,
    this.remote,
    this.sidecar, {
    required this.deviceId,
    required this.localProfileId,
    required this.patientId,
    required this.scope,
    required this.mayUpload,
    this.boundSinceMs = 0,
    this.unconfirmedPlans = const {},
  });
  final PracticeRepository repository;
  final RemoteApi remote;
  final SyncStore sidecar;
  final String deviceId, localProfileId, patientId;

  final String scope;
  final bool Function() mayUpload;
  final int boundSinceMs;
  final Set<String> unconfirmedPlans;

  Future<SyncOutcome> syncAll() async {
    final db = repository.db;
    int uploaded = 0, skipped = 0;
    final errors = <String>[];
    // A separate cursor per record type is not needed for this initial sync:
    // the sidecar records completed uploads, so re-scanning is idempotent and
    // resumes after network loss without touching the validated local DB.
    final definitions = <(String, String, String)>[
      ('sessions', 'session_id', 'PIANO_SESSION'),
      ('piece_performances', 'session_id', 'PIECE_PERFORMANCE'),
      ('dance_sessions', 'session_id', 'DANCE_SESSION'),
      ('training_plans', 'plan_id', 'TRAINING_PLAN'),
      ('plan_occurrences', 'occurrence_id', 'TRAINING_PLAN_EVENT'),
    ];
    for (final definition in definitions) {
      final (table, pk, type) = definition;
      String after = '';
      while (mayUpload()) {
        final rows = table == 'plan_occurrences'
            ? await db.rawQuery(
                'SELECT o.* FROM plan_occurrences o JOIN training_plans p ON p.plan_id=o.plan_id WHERE p.profile_id=? AND o.occurrence_id>? ORDER BY o.occurrence_id LIMIT 50',
                [localProfileId, after],
              )
            : await db.query(
                table,
                where: table == 'training_plans'
                    ? 'profile_id=? AND $pk>?'
                    : 'profile_id=? AND $pk>? AND started_utc_ms>=?',
                whereArgs: [
                  localProfileId,
                  after,
                  if (table != 'training_plans') boundSinceMs,
                ],
                orderBy: pk,
                limit: 50,
              );
        if (rows.isEmpty) break;
        after = rows.last[pk] as String;
        for (final row in rows) {
          if (!mayUpload()) return SyncOutcome(uploaded, skipped, errors);
          final id = row[pk] as String;
          if (unconfirmedPlans.contains(
            table == 'training_plans' ? id : row['plan_id'],
          )) {
            skipped++;
            continue;
          }
          // Do not upload unfinished sessions or corrupted records as if complete.
          if (table == 'sessions' &&
              ![
                'COMPLETED',
                'EXITED',
                'RECOVERED_INTERRUPTED',
              ].contains(row['status'])) {
            skipped++;
            continue;
          }
          if (table != 'training_plans' &&
              table != 'plan_occurrences' &&
              await sidecar.known(scope, type, id)) {
            skipped++;
            continue;
          }
          try {
            final Map<String, dynamic> payload;
            if (table == 'sessions') {
              final detail = await repository.detail(id);
              if (detail == null || detail['record_unavailable'] == true) {
                throw const FormatException('原始训练记录校验未通过');
              }
              final children = <String, List<Map<String, Object?>>>{};
              for (final child in [
                'blocks',
                'trials',
                'attempts',
                'events',
                'summaries',
                'adaptive_decisions',
              ]) {
                children[child] = await db.query(
                  child,
                  where: 'session_id=?',
                  whereArgs: [id],
                );
              }
              payload = {'record': detail, 'children': children};
            } else if (table == 'piece_performances' ||
                table == 'dance_sessions') {
              final detail = await repository.detail(id);
              if (detail == null || detail['record_unavailable'] == true) {
                throw const FormatException('演奏或舞蹈记录校验未通过');
              }
              payload = {'record': detail};
            } else if (table == 'training_plans') {
              final occurrences = await db.query(
                'plan_occurrences',
                where: 'plan_id=?',
                whereArgs: [id],
                orderBy: 'occurrence_id',
              );
              final plan = Map<String, dynamic>.from(
                jsonDecode(row['plan_json'] as String) as Map,
              );
              final now = DateTime.now();
              final firstAllowedDay = localDay(
                DateTime.fromMillisecondsSinceEpoch(boundSinceMs),
              );
              final dates =
                  [
                        for (var i = 6; i >= 0; i--)
                          DateTime(now.year, now.month, now.day - i),
                      ]
                      .where(
                        (day) =>
                            plan['deleted'] != true &&
                            planDue(plan, day) &&
                            localDay(day).compareTo(firstAllowedDay) >= 0,
                      )
                      .toList();
              final amounts =
                  await TrainingScheduleRepository(
                    db,
                    localProfileId,
                  ).automaticProgressFor([
                    for (final day in dates) (plan: plan, date: day),
                  ], notBeforeMs: boundSinceMs);
              payload = {
                'record': row,
                'occurrences': occurrences,
                'daily_progress': [
                  for (final (i, day) in dates.indexed)
                    {
                      'local_date': localDay(day),
                      'completed_units': amounts[i],
                      'target': plan['target'],
                      'target_type': plan['target_type'],
                    },
                ],
              };
            } else {
              final links = await db.rawQuery(
                '''SELECT l.* FROM plan_links l JOIN (
                    SELECT session_id, profile_id, started_utc_ms, 'exercise' AS kind FROM sessions
                    UNION ALL SELECT session_id, profile_id, started_utc_ms, 'piece' FROM piece_performances
                    UNION ALL SELECT session_id, profile_id, started_utc_ms, 'dance' FROM dance_sessions
                  ) r ON r.session_id=l.record_id AND r.kind=l.record_kind
                  WHERE l.occurrence_id=? AND r.profile_id=? AND r.started_utc_ms>=? ORDER BY l.rowid''',
                [id, localProfileId, boundSinceMs],
              );
              payload = {'record': row, 'links': links};
            }
            // Plans and occurrences can change. Emit append-only revisions using
            // a content-addressed source ID; completed sessions use stable IDs.
            final sourceId =
                (table == 'training_plans' || table == 'plan_occurrences')
                ? '$id:${sha256.convert(utf8.encode(jsonEncode(payload))).toString().substring(0, 24)}'
                : id;
            final body = <String, dynamic>{
              'device_id': deviceId,
              'local_profile_id': localProfileId,
              'patient_id': patientId,
              'source_record_id': sourceId,
              'record_type': type,
              'schema_version': 'flutter-v4',
              'task_version': row['task_version']?.toString(),
              'metric_version': row['metric_version']?.toString(),
              'captured_at_ms': row['started_utc_ms'],
              'payload': payload,
            };
            if (table == 'training_plans') {
              await sidecar.enqueuePlan(
                scope,
                id,
                sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
                body,
              );
            } else {
              await sidecar.enqueue(scope, body);
            }
          } catch (e) {
            errors.add('$type $id：$e');
            // Continue other independent records; the failed record stays pending.
          }
        }
      }
    }
    for (final entry in await sidecar.pending(scope)) {
      if (!mayUpload()) break;
      try {
        final body = Map<String, dynamic>.from(
          jsonDecode(entry['body'] as String) as Map,
        );
        // A locally deleted immutable record must not leave the device later.
        final kind = body['record_type'];
        final table = const {
          'PIANO_SESSION': 'sessions',
          'PIECE_PERFORMANCE': 'piece_performances',
          'DANCE_SESSION': 'dance_sessions',
        }[kind];
        if (table != null &&
            (await db.query(
              table,
              columns: ['session_id'],
              where: 'profile_id=? AND session_id=?',
              whereArgs: [localProfileId, body['source_record_id']],
              limit: 1,
            )).isEmpty) {
          await sidecar.acknowledge(scope, entry['seq'] as int);
          skipped++;
          continue;
        }
        if (!mayUpload()) break;
        final receipt = await remote.syncRecord(body);
        await sidecar.acknowledge(scope, entry['seq'] as int, receipt: receipt);
        uploaded++;
      } on RemoteApiException catch (e) {
        if (e.status == 401 || e.status == 403) rethrow;
        errors.add('上传失败（${e.status}）：${e.message}');
        if (e.status == 0 ||
            e.status == 408 ||
            e.status == 429 ||
            e.status >= 500) {
          await _retry(entry, e.status, e.retryAfter);
          break;
        }
        await sidecar.reject(scope, entry['seq'] as int, e.status);
      } catch (_) {
        errors.add('网络暂不可用，将保留待同步记录。');
        await _retry(entry, 0, null);
        break;
      }
    }
    final rejected = await sidecar.rejectedCount(scope);
    if (rejected > 0) errors.add('$rejected 条记录被服务器拒绝，已保留，需核对后处理。');
    return SyncOutcome(uploaded, skipped, errors);
  }

  Future<void> _retry(
    Map<String, Object?> entry,
    int status,
    Duration? retryAfter,
  ) {
    final attempt = (entry['retry_count'] as int) + 1;
    final base = min(900, 4 * (1 << min(attempt - 1, 8)));
    final delay = Duration(
      seconds: max(
        retryAfter?.inSeconds ?? 0,
        base + Random().nextInt(base ~/ 2 + 1),
      ),
    );
    return sidecar.postpone(scope, entry['seq'] as int, attempt, status, delay);
  }
}
