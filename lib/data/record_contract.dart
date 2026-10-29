import '../domain/contracts.dart';
import '../domain/cognitive_tasks.dart';
import 'record_integrity.dart';

/// The application checks types and cross-row invariants before SQLite writes.
/// SQLite's column affinity must never turn malformed strings into numbers.
class RecordContract {
  static Never fail(String field) =>
      throw FormatException('E_RECORD_CONTRACT: $field');
  static void integer(
    Json row,
    String key, {
    int min = 0,
    bool nullable = false,
  }) {
    final value = row[key];
    if (!row.containsKey(key) ||
        !(nullable && value == null) && !(value is int && value >= min)) {
      fail(key);
    }
  }

  static void string(Json row, String key, {bool nullable = false}) {
    final value = row[key];
    if (!row.containsKey(key) ||
        !(nullable && value == null) &&
            !(value is String && value.isNotEmpty)) {
      fail(key);
    }
  }

  static void enumeration(Json row, String key, Set<String> values) {
    if (!values.contains(row[key])) fail(key);
  }

  static void version(Json row) {
    if (row['schema_version'] != 1) fail('schema_version');
    canonical(row);
  }

  static void keys(Object? value, {bool empty = false}) {
    if (value is! List ||
        (!empty && value.isEmpty) ||
        value.any((v) => v is! int || v < 0 || v > 6)) {
      fail('key_ids');
    }
  }

  static void result(Json result, String taskId) {
    version(result);
    for (final key in [
      'response_action_count',
      'outside_count',
      'disabled_count',
      'overlap_count',
      'extra_count',
      'active_duration_us',
      'help_count',
      'policy_hint_count',
      'interrupted_retry_count',
    ]) {
      integer(result, key);
    }
    integer(result, 'first_down_offset_us', nullable: true);
    for (final key in ['paused_duration_us', 'user_pause_count']) {
      if (result.containsKey(key)) integer(result, key);
    }
    if (result['assisted'] is! bool) fail('assisted');
    final holdRule = result['hold_policy'] == 'HOLD_400_V1';
    final shortPresses = result['short_press_count'] as int? ?? 0;
    if (holdRule) {
      integer(result, 'short_press_count');
      integer(result, 'first_hold_us', nullable: true);
      if (result['required_hold_us'] != 400000 ||
          result['hold_complete'] is! bool) {
        fail('hold policy');
      }
      if (result['outcome'] == 'HIT' &&
              (result['hold_complete'] != true ||
                  result['first_hold_us'] == null ||
                  result['first_hold_us'] < 400000) ||
          result['outcome'] == 'TOO_SHORT' &&
              (result['hold_complete'] != false ||
                  shortPresses != 1 ||
                  result['first_hold_us'] == null ||
                  result['first_hold_us'] >= 400000)) {
        fail('hold outcome');
      }
    }
    final invalidActions = [
      'outside_count',
      'disabled_count',
      'overlap_count',
      'extra_count',
    ].fold<int>(0, (n, key) => n + (result[key] as int));
    if (taskId == 'G1_MEMORY') {
      enumeration(result, 'outcome', {
        'FULL_CORRECT',
        'SEQUENCE_ERROR',
        'TIMEOUT',
      });
      keys(result['expected_keys']);
      keys(result['consumed_keys'], empty: true);
      for (final key in [
        'position_correct_count',
        'expected_position_count',
        'omitted_position_count',
        'longest_correct_prefix',
      ]) {
        integer(result, key);
      }
      final expected = result['expected_keys'] as List;
      final consumed = result['consumed_keys'] as List;
      if (result['response_action_count'] !=
          consumed.length + invalidActions + shortPresses) {
        fail('response actions');
      }
      if (consumed.length > expected.length ||
          result['expected_position_count'] != expected.length ||
          result['omitted_position_count'] !=
              expected.length - consumed.length) {
        fail('positions');
      }
      var positions = 0, prefix = 0;
      for (var i = 0; i < consumed.length; i++) {
        if (consumed[i] == expected[i]) positions++;
        if (prefix == i && consumed[i] == expected[i]) prefix++;
      }
      if (result['position_correct_count'] != positions ||
          result['longest_correct_prefix'] != prefix ||
          result['full_correct'] is! bool ||
          (result['outcome'] == 'FULL_CORRECT') !=
              (result['full_correct'] == true)) {
        fail('G1 result');
      }
      if (result['full_correct'] == true &&
          (positions != expected.length ||
              shortPresses != 0 ||
              [
                'outside_count',
                'disabled_count',
                'overlap_count',
                'extra_count',
              ].any((k) => result[k] != 0))) {
        fail('full_correct');
      }
    } else if (isDualTask(taskId)) {
      enumeration(result, 'outcome', {
        'HIT',
        'OMISSION',
        'WRONG_OR_EXTRA',
        'OUT_OF_SYNC',
      });
      for (final key in ['left_target', 'right_target', 'gap_tolerance_us']) {
        integer(result, key);
      }
      for (final key in ['left_down_us', 'right_down_us', 'gap_us']) {
        integer(result, key, nullable: true);
      }
      keys(result['consumed_keys'], empty: true);
      final consumed = List<int>.from(result['consumed_keys']);
      final expectedKeys = [
        result['left_target'] as int,
        result['right_target'] as int,
      ];
      final actions = result['response_action_count'] as int;
      final invalid = result['outside_count'] + result['disabled_count'] as int;
      final eligible =
          actions == 2 &&
          invalid == 0 &&
          consumed.length == 2 &&
          consumed.toSet().containsAll(expectedKeys);
      if (result.containsKey('hold_policy') ||
          result['left_target'] > 2 ||
          result['right_target'] != result['left_target'] + 3 ||
          result['active_duration_us'] != 3000000 ||
          consumed.any((k) => k > 5) ||
          actions != consumed.length + invalid ||
          result['overlap_count'] != 0 ||
          result['extra_count'] !=
              (consumed.length > 2 ? consumed.length - 2 : 0) ||
          eligible != (result['gap_us'] != null)) {
        fail('dual responses');
      }
      for (final key in ['left_down_us', 'right_down_us']) {
        if (result[key] != null &&
            result[key] >= result['active_duration_us']) {
          fail('dual response time');
        }
      }
      if (eligible &&
          (result['left_down_us'] == null ||
              result['right_down_us'] == null ||
              result['gap_us'] !=
                  (result['left_down_us'] - result['right_down_us']).abs())) {
        fail('dual gap');
      }
      if (result['outcome'] !=
          dualOutcome(
            expectedKeys,
            consumed,
            actions,
            invalid,
            result['gap_us'],
            result['gap_tolerance_us'],
          )) {
        fail('dual outcome');
      }
    } else if (isWindowedTask(taskId)) {
      enumeration(
        result,
        'trial_type',
        taskId == 'G2_INHIBITION' ? {'GO', 'NO_GO'} : {'GO'},
      );
      integer(result, 'target_key', nullable: result['trial_type'] == 'NO_GO');
      integer(result, 'first_response_key', nullable: true);
      integer(result, 'rt_us', nullable: true);
      keys(result['consumed_keys'], empty: true);
      final consumed = (result['consumed_keys'] as List).cast<int>();
      if (consumed.any((k) => k > 2) ||
          result['target_key'] != null && result['target_key'] > 2 ||
          result['first_response_key'] !=
              (consumed.isEmpty ? null : consumed.first) ||
          result['extra_count'] !=
              (consumed.isEmpty ? 0 : consumed.length - 1) ||
          result['response_action_count'] !=
              consumed.length +
                  result['outside_count'] +
                  result['disabled_count'] +
                  result['overlap_count']) {
        fail('window responses');
      }
      if (result['trial_type'] == 'NO_GO' && result['target_key'] != null) {
        fail('no-go target');
      }
      var expected = windowOutcome(
        result,
        result['response_action_count'],
        consumed,
        result['outside_count'] +
            result['disabled_count'] +
            result['overlap_count'],
      );
      if (holdRule && expected == 'HIT' && result['hold_complete'] == false) {
        expected = 'TOO_SHORT';
      }
      if (result['outcome'] != expected ||
          (expected == 'HIT') != (result['rt_us'] != null) ||
          result['rt_us'] != null &&
              result['rt_us'] >= result['active_duration_us']) {
        fail('window outcome');
      }
      if (taskId == 'G3_SWITCH') {
        enumeration(result, 'rule_id', {'POSITION', 'SHAPE'});
        integer(result, 'r');
        integer(result, 's');
        if (result['r'] > 2 ||
            result['s'] > 2 ||
            result['r'] == result['s'] ||
            result['target_key'] !=
                (result['rule_id'] == 'POSITION' ? result['r'] : result['s']) ||
            !result.containsKey('switch_flag') ||
            result['switch_flag'] != null && result['switch_flag'] is! bool) {
          fail('switch result');
        }
      }
    } else if (isBeatTask(taskId)) {
      integer(result, 'target_key');
      integer(result, 'target_time_us');
      integer(result, 'first_response_key', nullable: true);
      integer(result, 'beat_error_us', min: -400000, nullable: true);
      keys(result['consumed_keys'], empty: true);
      final consumed = (result['consumed_keys'] as List).cast<int>();
      var expected = windowOutcome(
        {'trial_type': 'GO', 'target_key': result['target_key']},
        result['response_action_count'],
        consumed,
        result['outside_count'] +
            result['disabled_count'] +
            result['overlap_count'],
      );
      if (holdRule && expected == 'HIT' && result['hold_complete'] == false) {
        expected = 'TOO_SHORT';
      }
      if (result['target_key'] > (taskId == 'M1_ALTERNATE' ? 1 : 6) ||
          result['first_response_key'] !=
              (consumed.isEmpty ? null : consumed.first) ||
          result['response_action_count'] !=
              consumed.length +
                  result['outside_count'] +
                  result['disabled_count'] +
                  result['overlap_count'] ||
          result['extra_count'] !=
              (consumed.isEmpty ? 0 : consumed.length - 1) ||
          result['outcome'] != expected ||
          (expected == 'HIT') != (result['beat_error_us'] != null) ||
          result['beat_error_us'] != null &&
              result['beat_error_us'] >= 400000 ||
          result['active_duration_us'] != 800000 ||
          result['beat_reference'] != 'PLANNED_BEAT_REFERENCE') {
        fail('rhythm result');
      }
    } else {
      enumeration(result, 'outcome', {'COMPLETED_NOTE'});
      integer(result, 'target_key');
      if (result['target_key'] > 6) fail('target_key');
      integer(result, 'correct_down_count');
      integer(result, 'wrong_press_count');
      if (result['response_action_count'] !=
          1 + result['wrong_press_count'] + invalidActions + shortPresses) {
        fail('response actions');
      }
      if (result['correct_down_count'] != 1 ||
          result['first_pass'] is! bool ||
          result['response_action_count'] < 1) {
        fail('S1 result');
      }
      final firstPass =
          shortPresses == 0 &&
          result['response_action_count'] == 1 &&
          [
            'wrong_press_count',
            'outside_count',
            'disabled_count',
            'overlap_count',
            'extra_count',
          ].every((k) => result[k] == 0);
      if (result['first_pass'] != firstPass) fail('first_pass');
    }
  }

  static void validate(
    Json data,
    String sessionId,
    String epoch,
    String taskId,
    int slots,
    int maxLevel,
    String metricVersion,
  ) {
    if (!{
      'G1_MEMORY',
      'G2_INHIBITION',
      'G3_SWITCH',
      'S1_GUIDED',
      'S2_RHYTHM',
      'M1_ALTERNATE',
      'M2_DUAL_ZONE',
    }.contains(taskId)) {
      fail('task_id');
    }
    integer(data, 'level', min: 1);
    if (data['level'] > maxLevel) fail('level');
    integer(data, 'planned', min: 1);
    final blocks = <String, Json>{},
        trials = <String, Json>{},
        attempts = <String, Json>{};
    for (final b in (data['blocks'] as List).cast<Json>()) {
      string(b, 'block_id');
      if (blocks.containsKey(b['block_id']) || b['session_id'] != sessionId) {
        fail('block ownership');
      }
      blocks[b['block_id'] as String] = b;
      integer(b, 'ordinal');
      integer(b, 'slot_index');
      integer(b, 'level', min: 1);
      integer(b, 'planned_trial_count', min: 1);
      integer(b, 'valid_trial_count');
      integer(b, 'active_duration_us');
      if (b['slot_index'] >= slots || b['level'] > maxLevel) {
        fail('block range');
      }
      enumeration(b, 'status', {
        'PLANNED',
        'ACTIVE',
        'COMPLETED',
        'PARTIAL_MANUAL',
        'INTERRUPTED',
        'INVALID',
      });
      final targets = b['targets'] as Json;
      if (isDualTask(taskId) &&
          (b['planned_trial_count'] != 12 ||
              b['parameters']['response_window_ms'] != 3000 ||
              b['parameters']['gap_tolerance_us'] !=
                  [1000000, 800000, 600000, 400000][b['level'] - 1])) {
        fail('dual parameters');
      }
      if (isBeatTask(taskId) &&
          (b['parameters']['bpm'] != [40, 45, 50, 55][b['level'] - 1] ||
              b['parameters']['target_time_reference'] !=
                  'BLOCK_ACTIVE_BEAT_TIMELINE_V1')) {
        fail('rhythm parameters');
      }
      if (taskId == 'M1_ALTERNATE' &&
          (b['planned_trial_count'] != 12 ||
              canonical(b['parameters']['task']['pool']) != '[0,1]' ||
              b['parameters']['task']['planned_trial_count_per_block'] != 12)) {
        fail('alternate parameters');
      }
      version(targets);
      if (targets['rng_algorithm'] != 'rng-lcg32-1') fail('rng_algorithm');
      integer(targets, 'rng_state_before');
      integer(targets, 'rng_state_after');
      if (targets['rng_state_before'] > 0xffffffff ||
          targets['rng_state_after'] > 0xffffffff) {
        fail('rng state range');
      }
      if ((targets['trials'] as List).length != b['planned_trial_count']) {
        fail('targets');
      }
      if (isWindowedTask(taskId)) {
        final members = (targets['trials'] as List).cast<Json>();
        if (members.length != 12) fail('window block size');
        if (taskId == 'G2_INHIBITION') {
          if (members.where((t) => t['trial_type'] == 'GO').length != 9 ||
              members.where((t) => t['trial_type'] == 'NO_GO').length != 3) {
            fail('signal balance');
          }
          for (var key = 0; key < 3; key++) {
            if (members.where((t) => t['target_key'] == key).length != 3) {
              fail('go key balance');
            }
          }
          var run = 0;
          for (final t in members) {
            run = t['trial_type'] == 'NO_GO' ? run + 1 : 0;
            if (run > 2) fail('no-go run');
          }
        } else {
          if (b['parameters']['run_length'] !=
              [6, 4, 3, 2, 1][b['level'] - 1]) {
            fail('rule run length');
          }
          for (var r = 0; r < 3; r++) {
            for (var s = 0; s < 3; s++) {
              if (r != s &&
                  members.where((t) => t['r'] == r && t['s'] == s).length !=
                      2) {
                fail('shape pair balance');
              }
            }
          }
        }
      }
      if (b['status'] == 'COMPLETED') {
        string(b, 'commit_id');
        integer(b, 'ended_utc_ms');
        integer(b, 'ended_offset_us');
      }
    }
    for (final t in (data['trials'] as List).cast<Json>()) {
      string(t, 'trial_id');
      if (trials.containsKey(t['trial_id']) ||
          t['session_id'] != sessionId ||
          !blocks.containsKey(t['block_id'])) {
        fail('trial ownership');
      }
      trials[t['trial_id'] as String] = t;
      enumeration(t, 'status', {
        'PLANNED',
        'ACTIVE',
        'COMPLETED',
        'CANCELLED_MANUAL',
        'CANCELLED_RECONFIGURE',
        'INTERRUPTED',
      });
      integer(t, 'logical_index');
      for (final k in [
        'help_count',
        'policy_hint_count',
        'interrupted_retry_count',
      ]) {
        integer(t, k);
      }
      if (t['assisted'] != 0 && t['assisted'] != 1) fail('trial.assisted');
      final target = t['target'] as Json;
      version(target);
      keys(
        target['expected_keys'],
        empty: taskId == 'G2_INHIBITION' && target['trial_type'] == 'NO_GO',
      );
      enumeration(
        target,
        'trial_type',
        taskId == 'G1_MEMORY'
            ? {'SEQUENCE'}
            : taskId == 'G2_INHIBITION'
            ? {'GO', 'NO_GO'}
            : taskId == 'G3_SWITCH'
            ? {'GO'}
            : isDualTask(taskId)
            ? {'DUAL'}
            : {'NOTE'},
      );
      integer(target, 'logical_index');
      if (isDualTask(taskId)) {
        integer(target, 'left_target');
        integer(target, 'right_target');
        final left = t['logical_index'] % 3;
        if (target['left_target'] != left ||
            target['right_target'] != left + 3 ||
            canonical(target['expected_keys']) != canonical([left, left + 3])) {
          fail('dual target');
        }
      }
      if (!target.containsKey('rule_id') ||
          !target.containsKey('target_time_us') ||
          target['logical_index'] != t['logical_index']) {
        fail('target');
      }
      if (isWindowedTask(taskId)) {
        integer(
          target,
          'target_key',
          nullable: target['trial_type'] == 'NO_GO',
        );
        final expected = target['expected_keys'] as List;
        if (target['trial_type'] == 'NO_GO'
            ? target['target_key'] != null || expected.isNotEmpty
            : expected.length != 1 ||
                  target['target_key'] != expected.single ||
                  target['target_key'] > 2) {
          fail('window target');
        }
        if (taskId == 'G3_SWITCH') {
          integer(target, 'r');
          integer(target, 's');
          enumeration(target, 'rule_id', {'POSITION', 'SHAPE'});
          if (t['rule_id'] != target['rule_id'] ||
              t['switch_flag'] !=
                  (target['switch_flag'] == null
                      ? null
                      : target['switch_flag'] == true
                      ? 1
                      : 0)) {
            fail('trial rule columns');
          }
          final run = blocks[t['block_id']]!['parameters']['run_length'];
          if (run is! int ||
              run <= 0 ||
              target['r'] > 2 ||
              target['s'] > 2 ||
              target['r'] == target['s'] ||
              target['target_key'] !=
                  (target['rule_id'] == 'POSITION'
                      ? target['r']
                      : target['s']) ||
              target['rule_id'] !=
                  ((t['logical_index'] ~/ run).isEven ? 'POSITION' : 'SHAPE') ||
              target['switch_flag'] !=
                  (t['logical_index'] == 0
                      ? null
                      : t['logical_index'] % run == 0)) {
            fail('switch target');
          }
        }
      }
      if (isBeatTask(taskId)) {
        final parameters = blocks[t['block_id']]!['parameters'];
        integer(target, 'target_time_us');
        integer(target, 'target_key');
        if ((target['expected_keys'] as List).length != 1 ||
            target['target_key'] != (target['expected_keys'] as List).single ||
            target['duration_ms'] != 400 ||
            target['target_time_us'] !=
                1000000 +
                    t['logical_index'] *
                        60000000 ~/
                        (parameters['bpm'] as int)) {
          fail('rhythm target');
        }
        if (taskId == 'M1_ALTERNATE' &&
            target['target_key'] != t['logical_index'] % 2) {
          fail('alternate target');
        }
      }
      final generated = blocks[t['block_id']]!['targets']['trials'] as List;
      if (t['logical_index'] >= generated.length ||
          canonical(generated[t['logical_index']]) != canonical(target)) {
        fail('generated target');
      }
    }
    var open = 0;
    for (final a in (data['attempts'] as List).cast<Json>()) {
      string(a, 'attempt_id');
      final t = trials[a['trial_id']];
      if (attempts.containsKey(a['attempt_id']) ||
          a['session_id'] != sessionId ||
          t == null ||
          a['block_id'] != t['block_id']) {
        fail('attempt ownership');
      }
      attempts[a['attempt_id'] as String] = a;
      enumeration(a, 'validity', {'OPEN', 'VALID', 'INTERRUPTED', 'INVALID'});
      integer(a, 'ordinal');
      integer(a, 'started_offset_us');
      integer(a, 'active_duration_us');
      integer(a, 'ended_offset_us', nullable: true);
      if (a['ended_offset_us'] != null &&
          a['ended_offset_us'] < a['started_offset_us']) {
        fail('attempt time');
      }
      if (a['result_version'] != metricVersion) fail('result_version');
      if (a['validity'] == 'OPEN') {
        open++;
      } else if (a['validity'] == 'VALID') {
        integer(a, 'cue_anchor_us');
        integer(a, 'response_end_us');
        integer(a, 'ended_offset_us');
        result(a['result'] as Json, taskId);
        if (!isDualTask(taskId) &&
            {'metrics-2.0.0', 'metrics-2.1.0'}.contains(metricVersion) &&
            a['result']['hold_policy'] != 'HOLD_400_V1') {
          fail('required hold rule');
        }
        if (isBeatTask(taskId) &&
            a['result']['target_time_us'] != t['target']['target_time_us']) {
          fail('rhythm result target');
        }
        if (isDualTask(taskId)
            ? [
                    'left_target',
                    'right_target',
                  ].any((key) => a['result'][key] != t['target'][key]) ||
                  a['result']['gap_tolerance_us'] !=
                      blocks[t['block_id']]!['parameters']['gap_tolerance_us']
            : isWindowedTask(taskId)
            ? a['result']['target_key'] != t['target']['target_key'] ||
                  a['result']['trial_type'] != t['target']['trial_type'] ||
                  taskId == 'G3_SWITCH' &&
                      [
                        'rule_id',
                        'r',
                        's',
                        'switch_flag',
                      ].any((key) => a['result'][key] != t['target'][key])
            : taskId == 'G1_MEMORY'
            ? canonical(a['result']['expected_keys']) !=
                  canonical(t['target']['expected_keys'])
            : a['result']['target_key'] !=
                  (t['target']['expected_keys'] as List).single) {
          fail('result target');
        }
        if (a['outcome'] != a['result']['outcome'] ||
            a['active_duration_us'] != a['result']['active_duration_us'] ||
            a['active_duration_us'] !=
                a['response_end_us'] -
                    a['cue_anchor_us'] -
                    (a['result']['paused_duration_us'] ?? 0)) {
          fail('attempt result');
        }
      } else {
        string(a, 'reason_code');
        if (a['outcome'] != null || a['result'] != null) {
          fail('interrupted outcome');
        }
      }
    }
    if (open > 1) fail('open attempts');
    for (final t in trials.values) {
      final valid = attempts.values
          .where(
            (a) => a['trial_id'] == t['trial_id'] && a['validity'] == 'VALID',
          )
          .length;
      if (valid > 1 || (t['status'] == 'COMPLETED') != (valid == 1)) {
        fail('completed trial');
      }
    }
    for (final b in blocks.values) {
      final members = trials.values
          .where((t) => t['block_id'] == b['block_id'])
          .toList();
      final valid = attempts.values
          .where(
            (a) => a['block_id'] == b['block_id'] && a['validity'] == 'VALID',
          )
          .toList();
      if (members.length != b['planned_trial_count'] ||
          valid.length != b['valid_trial_count'] ||
          valid.fold<int>(0, (n, a) => n + (a['active_duration_us'] as int)) !=
              b['active_duration_us'] ||
          b['status'] == 'COMPLETED' && valid.length != members.length) {
        fail('block totals');
      }
    }
    if (data['finish'] != null) {
      enumeration(data, 'finish', {'COMPLETED', 'EXITED'});
      if (open != 0) fail('terminal open attempt');
      if (data['finish'] == 'COMPLETED') {
        for (var slot = 0; slot < slots; slot++) {
          if (blocks.values
                  .where(
                    (b) =>
                        b['slot_index'] == slot && b['status'] == 'COMPLETED',
                  )
                  .length !=
              1) {
            fail('completed slots');
          }
        }
        if (trials.values.where((t) => t['status'] == 'COMPLETED').length !=
            data['planned']) {
          fail('completed plan');
        }
      }
    }
    final events = (data['events'] as List).cast<Json>();
    final bySeq = <int, Json>{};
    const kinds = {
      'SESSION_CREATED',
      'STATE_CHANGED',
      'RULE_HEADER',
      'INTERTRIAL_PRESS',
      'BEAT_SCHEDULED',
      'BEAT_WINDOW_OPENED',
      'BEAT_REFERENCE',
      'OUT_OF_WINDOW',
      'HOLD_TOO_SHORT',
      'METRONOME_TICK',
      'BLOCK_CREATED',
      'TRIAL_CREATED',
      'ATTEMPT_STARTED',
      'CUE_REQUESTED',
      'CUE_PRESENTED',
      'POINTER_DOWN',
      'POINTER_MOVE',
      'POINTER_UP',
      'POINTER_CANCEL',
      'KEY_DOWN',
      'KEY_UP',
      'OUTSIDE_PRESS',
      'AUDIO_REQUEST',
      'AUDIO_REPLY',
      'HELP_REQUESTED',
      'DEMO_REPLAY_REQUESTED',
      'POLICY_HINT',
      'ATTEMPT_FINALIZED',
      'TRIAL_FINALIZED',
      'ADAPTIVE_DECISION',
      'PAUSE_REQUESTED',
      'RESUME_REQUESTED',
      'BLOCK_COMMITTED',
      'SESSION_FINALIZED',
      'ENVIRONMENT_RECONFIGURED',
      'ERROR',
    };
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (e['seq'] != i + 1 ||
          e['session_id'] != sessionId ||
          e['clock_epoch_id'] != epoch) {
        fail('event envelope');
      }
      integer(e, 'offset_us');
      if (i > 0 && e['offset_us'] < events[i - 1]['offset_us']) {
        fail('event clock');
      }
      enumeration(e, 'kind', kinds);
      if (e['payload_version'] != 1 || e['payload'] is! Json) {
        fail('payload_version');
      }
      RecordIntegrity.event(e);
      if (e['block_id'] != null && !blocks.containsKey(e['block_id'])) {
        fail('event block');
      }
      if (e['trial_id'] != null &&
          trials[e['trial_id']]?['block_id'] != e['block_id']) {
        fail('event trial');
      }
      if (e['attempt_id'] != null &&
          attempts[e['attempt_id']]?['trial_id'] != e['trial_id']) {
        fail('event attempt');
      }
      final source = e['source_event_seq'];
      if (source != null) {
        if (source is! int ||
            source >= e['seq'] ||
            !bySeq.containsKey(source)) {
          fail('source_event_seq');
        }
        final raw = bySeq[source]!;
        final expectedKind = e['kind'] == 'KEY_UP'
            ? 'POINTER_UP'
            : 'POINTER_DOWN';
        if (raw['kind'] != expectedKind ||
            raw['attempt_id'] != e['attempt_id'] ||
            raw['payload']['pointer_id'] != e['payload']['pointer_id']) {
          fail('source input');
        }
      }
      if ({'KEY_DOWN', 'KEY_UP', 'OUTSIDE_PRESS'}.contains(e['kind']) &&
          source == null) {
        fail('input source');
      }
      bySeq[e['seq'] as int] = e;
    }
    if (events.isEmpty || events.first['kind'] != 'SESSION_CREATED') {
      fail('first event');
    }
    final decisionKeys = <String>{};
    for (final d in (data['decisions'] as List? ?? []).cast<Json>()) {
      for (final k in [
        'decision_id',
        'decision_key',
        'adaptive_version',
        'reason_code',
      ]) {
        string(d, k);
      }
      enumeration(d, 'source', {'AUTO', 'USER'});
      enumeration(d, 'action', {'UP', 'DOWN', 'HOLD', 'ASSIST'});
      integer(d, 'level_before', min: 1);
      integer(d, 'level_after', min: 1);
      integer(d, 'decided_offset_us');
      if (d['session_id'] != sessionId ||
          !blocks.containsKey(d['block_id']) ||
          d['level_before'] > maxLevel ||
          d['level_after'] > maxLevel ||
          !decisionKeys.add(d['decision_key'] as String) ||
          d['parameters_before'] is! Json ||
          d['parameters_after'] is! Json ||
          d['evidence'] is! Json) {
        fail('adaptive decision');
      }
      if (d['source'] == 'AUTO' &&
          (blocks[d['block_id']]!['status'] != 'COMPLETED' ||
              d['decision_key'] != blocks[d['block_id']]!['commit_id'])) {
        fail('decision commit');
      }
    }
    canonical(data);
  }
}
