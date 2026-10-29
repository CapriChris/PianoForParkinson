import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';
import '../domain/piece_performance.dart';
import 'database_safety.dart';
import 'record_contract.dart';
import 'record_integrity.dart';

List<String> auditRows(Json request) {
  final issues = <String>[];
  for (final raw in request['rows'] as List) {
    final row = Map<String, dynamic>.from(raw as Map);
    try {
      switch (request['table']) {
        case 'piece_performances':
          PiecePerformance.fromRow(row);
        case 'sessions':
          RecordIntegrity.session(row);
        case 'summaries':
          RecordIntegrity.summary(
            jsonDecode(row['result_json'] as String) as Json,
            row['metric_version'] as String,
          );
          final summary = jsonDecode(row['result_json'] as String) as Json;
          if (row['scope'] == 'BLOCK' &&
              summary['comparison_key'] != row['comparison_key']) {
            RecordContract.fail('summary comparison key');
          }
        case 'attempts':
          if (row['validity'] == 'VALID') {
            RecordContract.result(
              jsonDecode(row['result_json'] as String) as Json,
              row['task_id'] as String,
            );
          }
        case 'events':
          final payload = jsonDecode(row['payload_json'] as String) as Json;
          RecordIntegrity.event({'payload': payload});
          if (row['seq'] == 1 && row['kind'] != 'SESSION_CREATED') {
            RecordContract.fail('first event');
          }
          if (row['source_event_seq'] != null) {
            final source =
                jsonDecode(row['audit_source_json'] as String) as Json;
            final expected = row['kind'] == 'KEY_UP'
                ? 'POINTER_UP'
                : 'POINTER_DOWN';
            if (row['audit_source_kind'] != expected ||
                row['audit_source_attempt'] != row['attempt_id'] ||
                source['pointer_id'] != payload['pointer_id']) {
              RecordContract.fail('source input');
            }
          }
          if (row['seq'] is! int ||
              row['seq'] < 1 ||
              row['payload_version'] != 1) {
            RecordContract.fail('event envelope');
          }
          if (row['offset_us'] != null &&
              (row['offset_us'] is! int || row['offset_us'] < 0)) {
            RecordContract.fail('event offset');
          }
        case 'blocks':
          final params = jsonDecode(row['parameters_json'] as String) as Json;
          if (params['layout_snapshot'] != null) {
            RecordIntegrity.layout(
              params['layout_snapshot'] as Json,
              legacy: true,
            );
          }
          RecordContract.version(
            jsonDecode(row['targets_json'] as String) as Json,
          );
        case 'trials':
          RecordContract.version(
            jsonDecode(row['target_json'] as String) as Json,
          );
        case 'adaptive_decisions':
          for (final key in [
            'parameters_before_json',
            'parameters_after_json',
            'evidence_json',
          ]) {
            canonical(jsonDecode(row[key] as String));
          }
        case 'profiles':
          RecordIntegrity.profile(row);
      }
    } catch (error) {
      issues.add('${request['table']}: $error');
    }
  }
  return issues;
}

class RecordAudit {
  static Future<Json> run(
    DatabaseSafety safety, {
    bool Function()? cancelled,
  }) async {
    final database = await safety.openReadOnly();
    var checked = 0, issueCount = 0;
    final details = <String>[];
    try {
      await database.transaction((tx) async {
        await DatabaseSafety.verify(tx);
        for (final sql in [
          'SELECT session_id FROM events GROUP BY session_id HAVING MIN(seq)<>1 OR MAX(seq)<>COUNT(*)',
          'SELECT n.session_id FROM events n JOIN events p ON n.session_id=p.session_id AND n.seq=p.seq+1 WHERE n.clock_epoch_id=p.clock_epoch_id AND n.offset_us IS NOT NULL AND p.offset_us IS NOT NULL AND n.offset_us<p.offset_us GROUP BY n.session_id',
        ]) {
          final violations = await tx.rawQuery(
            'SELECT COUNT(*) AS n FROM ($sql)',
          );
          final count = violations.single['n'] as int;
          issueCount += count;
          if (count > 0 && details.length < 100) {
            details.add('events: E_RECORD_CONTRACT: sequence/clock order');
          }
        }
        for (final table in [
          'profiles',
          'piece_performances',
          'sessions',
          'blocks',
          'trials',
          'attempts',
          'events',
          'summaries',
          'adaptive_decisions',
        ]) {
          var cursor = 0;
          while (true) {
            if (cancelled?.call() == true) {
              throw StateError('E_AUDIT_CANCELLED');
            }
            final query = switch (table) {
              'attempts' => 'SELECT a.rowid AS audit_rowid,a.*,s.task_id FROM attempts a JOIN sessions s ON a.session_id=s.session_id WHERE a.rowid>? ORDER BY a.rowid LIMIT 200',
              'events' => 'SELECT e.rowid AS audit_rowid,e.*,p.payload_json AS audit_source_json,p.kind AS audit_source_kind,p.attempt_id AS audit_source_attempt FROM events e LEFT JOIN events p ON e.session_id=p.session_id AND e.source_event_seq=p.seq WHERE e.rowid>? ORDER BY e.rowid LIMIT 200',
              _ =>
                'SELECT rowid AS audit_rowid,* FROM $table WHERE rowid>? ORDER BY rowid LIMIT 200',
            };
            final rows = await tx.rawQuery(query, [cursor]);
            if (rows.isEmpty) break;
            checked += rows.length;
            final found = await compute(auditRows, {
              'table': table,
              'rows': rows,
            });
            issueCount += found.length;
            details.addAll(found.take((100 - details.length).clamp(0, 100)));
            cursor = rows.last['audit_rowid'] as int;
          }
        }
      }, exclusive: false);
      return {
        'checked': checked,
        'issues': issueCount,
        'details': details,
        'complete': true,
      };
    } catch (error) {
      return {
        'checked': checked,
        'issues': issueCount + 1,
        'details': [...details, '$error'],
        'complete': false,
      };
    } finally {
      await database.close();
    }
  }
}
