/// Preserve local v4 data and upload validated, versioned immutable snapshots.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/practice_repository.dart';
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
  });
  final PracticeRepository repository;
  final RemoteApi remote;
  final SyncStore sidecar;
  final String deviceId, localProfileId, patientId;

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
      List<Map<String, Object?>> rows;
      if (table == 'plan_occurrences') {
        rows = await db.rawQuery(
          'SELECT o.* FROM plan_occurrences o JOIN training_plans p ON p.plan_id=o.plan_id WHERE p.profile_id=? ORDER BY o.occurrence_id',
          [localProfileId],
        );
      } else {
        rows = await db.query(
          table,
          where: 'profile_id=?',
          whereArgs: [localProfileId],
          orderBy: pk,
        );
      }
      for (final row in rows) {
        final id = row[pk] as String;
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
            );
            payload = {'record': row, 'occurrences': occurrences};
          } else {
            final links = await db.query(
              'plan_links',
              where: 'occurrence_id=?',
              whereArgs: [id],
            );
            payload = {'record': row, 'links': links};
          }
          // Plans and occurrences can change. Emit append-only revisions using
          // a content-addressed source ID; completed sessions use stable IDs.
          final sourceId =
              (table == 'training_plans' || table == 'plan_occurrences')
              ? '$id:${sha256.convert(utf8.encode(jsonEncode(payload))).toString().substring(0, 24)}'
              : id;
          if (await sidecar.isSynced(type, sourceId, patientId)) {
            skipped++;
            continue;
          }
          await remote.syncRecord({
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
          });
          await sidecar.markSynced(type, sourceId, patientId);
          uploaded++;
        } catch (e) {
          errors.add('$type $id：$e');
          // Continue other independent records; the failed record stays pending.
        }
      }
    }
    return SyncOutcome(uploaded, skipped, errors);
  }
}
