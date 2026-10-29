import 'dart:convert';

import '../domain/contracts.dart';
import '../domain/practice_metrics.dart';
import 'record_contract.dart';

/// Pure worker entry point. Only JSON data crosses the isolate boundary;
/// database handles, the live clock and the mutable engine stay on the UI isolate.
Json prepareRecordSnapshot(Json request) {
  final raw = normalizeRecordText(request['data']) as Json;
  raw['summary'] = PracticeMetrics.build(
    taskId: request['task_id'],
    version: request['metric_version'],
    attempts: (raw['attempts'] as List).cast<Json>(),
    trials: (raw['trials'] as List).cast<Json>(),
    events: (raw['events'] as List).cast<Json>(),
    planned: raw['planned'],
    complete: raw['finish'] == 'COMPLETED',
    qualityFlags: raw['resource_limited'] == true
        ? ['SESSION_RESOURCE_LIMIT']
        : [],
  );
  final data = jsonDecode(canonical(raw)) as Json;
  RecordContract.validate(
    data,
    request['id'],
    request['epoch'],
    request['task_id'],
    request['slots'],
    request['maximum'],
    request['metric_version'],
  );
  if (request['prepare_rows'] == true) {
    final rows = <String, dynamic>{};
    for (final entry in {
      'blocks': (
        'block_id',
        {'parameters': 'parameters_json', 'targets': 'targets_json'},
      ),
      'trials': ('trial_id', {'target': 'target_json'}),
      'attempts': ('attempt_id', {'result': 'result_json'}),
      'events': ('seq', {'payload': 'payload_json'}),
      'adaptive_decisions': (
        'decision_id',
        {
          'parameters_before': 'parameters_before_json',
          'parameters_after': 'parameters_after_json',
          'evidence': 'evidence_json',
        },
      ),
    }.entries) {
      final table = <String, dynamic>{};
      for (final source
          in data[entry.key == 'adaptive_decisions' ? 'decisions' : entry.key]
              as List) {
        final values = Map<String, dynamic>.from(source);
        for (final field in entry.value.$2.entries) {
          final value = values.remove(field.key);
          values[field.value] = value == null ? null : canonical(value);
        }
        table['${values[entry.value.$1]}'] = {
          'values': values,
          'fingerprint': canonical(values),
        };
      }
      rows[entry.key] = table;
    }
    data['_prepared_rows'] = rows;
  }
  return data;
}
