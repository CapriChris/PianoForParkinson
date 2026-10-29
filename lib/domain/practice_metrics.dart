import 'dart:math';

import 'contracts.dart';
import 'cognitive_tasks.dart';

/// Integer-only statistics. An empty sample is unknown, never zero latency.
Json timingStatistics(Iterable<int> samples) {
  final values = samples.toList()..sort();
  final n = values.length;
  final sum = values.fold<int>(0, (a, b) => a + b);
  final squares = values.fold<BigInt>(
    BigInt.zero,
    (a, b) => a + BigInt.from(b).pow(2),
  );
  final representable = squares <= BigInt.from(0x7fffffffffffffff);
  return {
    'samples': n,
    'sum_us': n == 0 ? null : sum,
    'sum_squared_us': n == 0 || !representable ? null : squares.toInt(),
    'quality_flags': representable ? <String>[] : ['SUM_SQUARED_OVERFLOW'],
    'median_numerator_us': n == 0
        ? null
        : n.isOdd
        ? values[n ~/ 2]
        : values[n ~/ 2 - 1] + values[n ~/ 2],
    'median_denominator': n == 0
        ? null
        : n.isOdd
        ? 1
        : 2,
    'p95_us': n == 0 ? null : values[(95 * n + 99) ~/ 100 - 1],
    'cv_ppm': n >= 10 && sum > 0
        ? (sqrt(
                    max(
                      0,
                      (BigInt.from(n) * squares - BigInt.from(sum).pow(2))
                              .toDouble() /
                          (n * (n - 1)),
                    ),
                  ) /
                  (sum / n) *
                  1000000)
              .round()
        : null,
  };
}

class PracticeMetrics {
  static Json build({
    required String taskId,
    required String version,
    required List<Json> attempts,
    required List<Json> trials,
    required List<Json> events,
    required int planned,
    required bool complete,
    String? comparisonKey,
    List<String> qualityFlags = const [],
  }) {
    final memory = taskId == 'G1_MEMORY';
    final inhibition = taskId == 'G2_INHIBITION',
        switching = taskId == 'G3_SWITCH';
    final rhythm = isBeatTask(taskId);
    final dual = isDualTask(taskId);
    final windowed = inhibition || switching || rhythm || dual;
    final valid = attempts.where((a) => a['validity'] == 'VALID').toList();
    final results = valid.map((a) => a['result'] as Json).toList();
    bool correct(Json r) => memory
        ? r['full_correct'] == true
        : windowed
        ? r['outcome'] == 'HIT'
        : r['first_pass'] == true;
    List<Json> primaryMembers(Iterable<Json> rows) =>
        rows.where((r) => !inhibition || r['trial_type'] == 'GO').toList();
    final primary = primaryMembers(results);
    int sum(String key) => results.fold<int>(0, (n, r) => n + (r[key] as int));
    Json rate(int numerator, int denominator) => {
      'numerator': numerator,
      'denominator': denominator,
    };
    final unassisted = results.where((r) => r['assisted'] == false).toList();
    final assisted = results.where((r) => r['assisted'] == true).toList();
    final response = <int>[],
        responseAssisted = <int>[],
        responseAlone = <int>[];
    final holds = <int>[];
    // Only matched DOWN/UP in a VALID attempt can form a hold sample.
    for (final attempt in valid) {
      final inputs = events.where(
        (e) => e['attempt_id'] == attempt['attempt_id'],
      );
      final down = <int, int>{};
      int? firstConsumed;
      var pausedBeforeFirst = 0;
      for (final event in inputs) {
        final p = event['payload'] as Json;
        final pointer = p['pointer_id'];
        if (event['kind'] == 'PAUSE_REQUESTED') {
          down.clear();
        } else if (event['kind'] == 'RESUME_REQUESTED' &&
            firstConsumed == null &&
            attempt['cue_anchor_us'] != null &&
            event['offset_us'] >= attempt['cue_anchor_us']) {
          pausedBeforeFirst += p['pause_duration_us'] as int? ?? 0;
        } else if (event['kind'] == 'KEY_DOWN') {
          down[pointer as int] = event['offset_us'] as int;
          if (p['overlap'] == false) {
            firstConsumed ??= event['offset_us'] as int;
          }
        } else if (event['kind'] == 'KEY_UP') {
          final start = down.remove(pointer);
          if (start != null) holds.add((event['offset_us'] as int) - start);
        } else if (event['kind'] == 'POINTER_CANCEL') {
          down.remove(pointer);
        }
      }
      if (memory && firstConsumed != null) {
        final elapsed =
            firstConsumed -
            (attempt['cue_anchor_us'] as int) -
            pausedBeforeFirst;
        response.add(elapsed);
        ((attempt['result'] as Json)['assisted'] == true
                ? responseAssisted
                : responseAlone)
            .add(elapsed);
      }
      if (windowed && (attempt['result'] as Json)['rt_us'] != null) {
        final r = attempt['result'] as Json;
        response.add(r['rt_us'] as int);
        (r['assisted'] == true ? responseAssisted : responseAlone).add(
          r['rt_us'] as int,
        );
      }
    }
    final go = results.where((r) => r['trial_type'] == 'GO').toList();
    final noGo = results.where((r) => r['trial_type'] == 'NO_GO').toList();
    Json outcomeRate(List<Json> members, String outcome) => rate(
      members.where((r) => r['outcome'] == outcome).length,
      members.length,
    );
    final switched = results
        .where(
          (r) =>
              switching &&
              r['switch_flag'] == true &&
              r['outcome'] == 'HIT' &&
              r['assisted'] == false,
        )
        .map((r) => r['rt_us'] as int)
        .toList();
    final repeated = results
        .where(
          (r) =>
              switching &&
              r['switch_flag'] == false &&
              r['outcome'] == 'HIT' &&
              r['assisted'] == false,
        )
        .map((r) => r['rt_us'] as int)
        .toList();
    final switchTiming = timingStatistics(switched),
        repeatTiming = timingStatistics(repeated);
    Json? switchDifference;
    if (switched.length >= 5 && repeated.length >= 5) {
      final a = switchTiming['median_numerator_us'] as int,
          b = switchTiming['median_denominator'] as int;
      final x = repeatTiming['median_numerator_us'] as int,
          y = repeatTiming['median_denominator'] as int;
      switchDifference = {'numerator_us': a * y - x * b, 'denominator': b * y};
    }
    final duration = sum('active_duration_us');
    final beatErrors = results
        .where((r) => r['beat_error_us'] != null)
        .map((r) => r['beat_error_us'] as int)
        .toList();
    final alternateIntervals = <int>[];
    if (taskId == 'M1_ALTERNATE') {
      final trialById = {for (final t in trials) t['trial_id']: t};
      Json? previous;
      final ordered = [...valid]
        ..sort(
          (a, b) => (a['started_offset_us'] as int).compareTo(
            b['started_offset_us'] as int,
          ),
        );
      for (final a in ordered) {
        final r = a['result'] as Json;
        final t = trialById[a['trial_id']]!;
        final eligible =
            r['outcome'] == 'HIT' &&
            r['assisted'] == false &&
            r['help_count'] == 0 &&
            r['interrupted_retry_count'] == 0 &&
            (r['user_pause_count'] ?? 0) == 0;
        if (eligible &&
            previous != null &&
            previous['block_id'] == a['block_id'] &&
            trialById[previous['trial_id']]!['logical_index'] + 1 ==
                t['logical_index']) {
          alternateIntervals.add(
            r['first_down_offset_us'] -
                    previous['result']['first_down_offset_us']
                as int,
          );
        }
        previous = eligible ? a : null;
      }
    }
    return {
      'version': version,
      'sample_counts': {
        'valid': results.length,
        'interrupted': attempts
            .where((a) => a['validity'] == 'INTERRUPTED')
            .length,
        'invalid': attempts.where((a) => a['validity'] == 'INVALID').length,
        'unassisted': unassisted.length,
        'assisted': assisted.length,
        'response_actions': sum('response_action_count'),
        if (inhibition) ...{'valid_go': go.length, 'valid_no_go': noGo.length},
      },
      'rates': {
        'primary': rate(primary.where(correct).length, primary.length),
        'unassisted_primary': rate(
          primaryMembers(unassisted).where(correct).length,
          primaryMembers(unassisted).length,
        ),
        'assisted_primary': rate(
          primaryMembers(assisted).where(correct).length,
          primaryMembers(assisted).length,
        ),
        if (memory)
          'position_accuracy': rate(
            sum('position_correct_count'),
            sum('expected_position_count'),
          ),
        if (!memory && !windowed)
          'correct_actions': rate(
            sum('correct_down_count'),
            sum('response_action_count'),
          ),
        if (inhibition) ...{
          'go_hit': outcomeRate(go, 'HIT'),
          'go_omission': outcomeRate(go, 'OMISSION'),
          'go_wrong_key': outcomeRate(go, 'WRONG_KEY'),
          'go_extra_response': outcomeRate(go, 'EXTRA_RESPONSE'),
          'no_go_commission': outcomeRate(noGo, 'COMMISSION'),
          'no_go_correct': outcomeRate(noGo, 'CORRECT_WITHHOLD'),
        },
        if (switching) ...{
          for (final rule in ['POSITION', 'SHAPE'])
            'rule_${rule.toLowerCase()}': outcomeRate(
              results.where((r) => r['rule_id'] == rule).toList(),
              'HIT',
            ),
          'switch': outcomeRate(
            results.where((r) => r['switch_flag'] == true).toList(),
            'HIT',
          ),
          'non_switch': outcomeRate(
            results.where((r) => r['switch_flag'] == false).toList(),
            'HIT',
          ),
        },
        if (rhythm) ...{
          'beat_omission': outcomeRate(results, 'OMISSION'),
          'beat_wrong_key': outcomeRate(results, 'WRONG_KEY'),
          'beat_extra_response': outcomeRate(results, 'EXTRA_RESPONSE'),
        },
      },
      'timings': timingStatistics(
        dual
            ? results
                  .where((r) => r['gap_us'] != null)
                  .map((r) => r['gap_us'] as int)
            : rhythm
            ? beatErrors.map((e) => e.abs())
            : windowed
            ? response
            : results.map((r) => r['active_duration_us'] as int),
      ),
      'timing_groups': {
        if (dual)
          'dual_gap': timingStatistics(
            results
                .where((r) => r['gap_us'] != null)
                .map((r) => r['gap_us'] as int),
          ),
        if (taskId == 'M1_ALTERNATE')
          'alternate_hit_interval': timingStatistics(alternateIntervals),
        'first_response': timingStatistics(response),
        'first_response_assisted': timingStatistics(responseAssisted),
        'first_response_unassisted': timingStatistics(responseAlone),
        'key_hold': timingStatistics(holds),
        if (rhythm) ...{
          'beat_error_absolute': timingStatistics(
            beatErrors.map((e) => e.abs()),
          ),
          'beat_error_absolute_unassisted': timingStatistics(
            results
                .where(
                  (r) => r['assisted'] == false && r['beat_error_us'] != null,
                )
                .map((r) => (r['beat_error_us'] as int).abs()),
          ),
        },
        if (windowed)
          'window_duration': timingStatistics(
            results.map((r) => r['active_duration_us'] as int),
          ),
        if (switching) ...{
          'switch_unassisted': switchTiming,
          'non_switch_unassisted': repeatTiming,
        },
      },
      if (switching) 'switch_median_difference': switchDifference,
      if (rhythm) ...{
        'beat_reference': 'PLANNED_BEAT_REFERENCE',
        'beat_direction_counts': {
          'early': beatErrors.where((e) => e < 0).length,
          'on_target': beatErrors.where((e) => e == 0).length,
          'late': beatErrors.where((e) => e > 0).length,
        },
      },
      if (windowed)
        'outcome_counts': {
          for (final outcome in [
            'HIT',
            'OMISSION',
            'WRONG_KEY',
            'EXTRA_RESPONSE',
            'TOO_SHORT',
            'CORRECT_WITHHOLD',
            'COMMISSION',
            if (dual) ...['WRONG_OR_EXTRA', 'OUT_OF_SYNC'],
          ])
            outcome: results.where((r) => r['outcome'] == outcome).length,
        },
      'assistance_counts': {
        'user_pause': results.fold<int>(
          0,
          (n, r) => n + (r['user_pause_count'] as int? ?? 0),
        ),
        'help': trials.fold<int>(0, (n, t) => n + (t['help_count'] as int)),
        'policy_hint': trials.fold<int>(
          0,
          (n, t) => n + (t['policy_hint_count'] as int),
        ),
        'interrupted_retry': trials.fold<int>(
          0,
          (n, t) => n + (t['interrupted_retry_count'] as int),
        ),
        'assisted_trials': assisted.length,
      },
      'error_counts': {
        'short_press': results.fold<int>(
          0,
          (n, r) => n + (r['short_press_count'] as int? ?? 0),
        ),
        'outside': sum('outside_count'),
        'disabled': sum('disabled_count'),
        'overlap': sum('overlap_count'),
        'extra': sum('extra_count'),
        if (rhythm)
          'out_of_window': events
              .where((e) => e['kind'] == 'OUT_OF_WINDOW')
              .length,
        if (memory) 'omitted_positions': sum('omitted_position_count'),
        if (!memory && !windowed) 'wrong_press': sum('wrong_press_count'),
      },
      if (memory)
        'longest_full_correct_sequence': results
            .where((r) => r['full_correct'] == true)
            .fold<int>(
              0,
              (n, r) => max(n, r['expected_position_count'] as int),
            ),
      'quality_flags': {...qualityFlags, if (!complete) 'PARTIAL'}.toList()
        ..sort(),
      'comparison_key': comparisonKey,
      'completed': results.length,
      'planned': planned,
      'active_duration_us': duration,
    };
  }

  /// Block conditions exclude random targets, seeds and per-session IDs.
  static String? comparisonKey(Json session, Json block, Json summary) {
    final snapshot = session['snapshot'] as Json;
    final environment = session['environment'] as Json;
    final parameters = block['parameters'] as Json;
    final layout = parameters['layout_snapshot'] as Json;
    const requiredEnvironment = [
      'device_local_id',
      'clock_source',
      'sound_enabled',
      'app_gain_permille',
      'audio_route_category',
      'layout_version',
    ];
    if (requiredEnvironment.any((k) => environment[k] == null) ||
        layout['layout_id'] == null ||
        environment['sound_enabled'] == true &&
            environment['audio_route_category'] == 'UNKNOWN') {
      return null;
    }
    final content = snapshot['content'] as Json?;
    final effectiveParameters = {...parameters};
    effectiveParameters['layout_snapshot'] = {
      for (final e in layout.entries)
        if (e.key != 'snapshot_id') e.key: e.value,
    };
    return digest({
      'task_id': snapshot['task_id'],
      'task_version': snapshot['task_version'],
      'content_id': content?['content_id'],
      'content_version': content?['version'],
      'mode': snapshot['mode'],
      'parameter_profile_version': snapshot['parameter_profile']['version'],
      'level': block['level'],
      'effective_parameters': effectiveParameters,
      'input_source': 'TOUCH',
      'layout_id': layout['layout_id'],
      'layout_version': environment['layout_version'],
      'pool': parameters['task']['pool'] ?? content?['notes'],
      'language': snapshot['instruction_locale'],
      'cue_channels': environment['sound_enabled'] == true
          ? ['VISUAL', 'AUDIO']
          : ['VISUAL'],
      for (final key in requiredEnvironment) key: environment[key],
      'metric_version': summary['version'],
      if (environment['renderer_policy'] != null)
        'renderer_policy': environment['renderer_policy'],
      if ({'metrics-2.0.0', 'metrics-2.1.0'}.contains(summary['version']))
        'sound_pack_version': environment['sound_pack_version'],
      ...summary['assistance_counts'] as Json,
    });
  }
}
