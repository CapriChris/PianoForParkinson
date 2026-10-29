import 'contracts.dart';

bool isWindowedTask(String id) => id == 'G2_INHIBITION' || id == 'G3_SWITCH';
bool isCognitiveTask(String id) => id.startsWith('G');
bool isBeatTask(String id) => id == 'S2_RHYTHM' || id == 'M1_ALTERNATE';
bool isDualTask(String id) => id == 'M2_DUAL_ZONE';

String taskTitle(String id, bool zh) => switch (id) {
  'PIANO_PIECE' => zh ? '钢琴曲目' : 'Piano piece',
  'G1_MEMORY' => zh ? '旋律记忆' : 'Melody memory',
  'G2_INHIBITION' => zh ? '弹奏与等待' : 'Play and wait',
  'G3_SWITCH' => zh ? '位置与图形' : 'Position and shape',
  'S2_RHYTHM' => zh ? '节奏练习' : 'Rhythm practice',
  'M1_ALTERNATE' => zh ? '交替按键' : 'Alternating keys',
  'M2_DUAL_ZONE' => zh ? '双区配合' : 'Two-zone coordination',
  _ => zh ? '短旋律练习' : 'A short melody',
};
String primaryMetricTitle(String id, bool zh) => switch (id) {
  'G1_MEMORY' => zh ? '完整正确序列' : 'Fully correct sequences',
  'G2_INHIBITION' => zh ? '弹奏信号命中' : 'Go signal hits',
  'G3_SWITCH' => zh ? '正确目标' : 'Correct targets',
  'S2_RHYTHM' => zh ? '节拍命中' : 'Beat hits',
  'M1_ALTERNATE' => zh ? '交替节拍命中' : 'Alternating beat hits',
  'M2_DUAL_ZONE' => zh ? '双区命中' : 'Two-zone hits',
  _ => zh ? '首次正确音符' : 'First-pass notes',
};

List<Json> dualTargets(Json task) =>
    List.generate(task['planned_trial_count_per_block'] as int, (i) {
      final pair = List<int>.from(task['target_pairs'][i % 3]);
      return <String, dynamic>{
        'schema_version': 1,
        'logical_index': i,
        'trial_type': 'DUAL',
        'expected_keys': pair,
        'left_target': pair[0],
        'right_target': pair[1],
        'rule_id': null,
        'target_time_us': null,
      };
    });

String dualOutcome(
  List<int> expected,
  List<int> consumed,
  int actions,
  int invalid,
  int? gap,
  int tolerance,
) {
  if (invalid > 0 ||
      actions > 2 ||
      consumed.any((k) => !expected.contains(k)) ||
      consumed.toSet().length != consumed.length) {
    return 'WRONG_OR_EXTRA';
  }
  if (consumed.length < 2) return 'OMISSION';
  return gap! <= tolerance ? 'HIT' : 'OUT_OF_SYNC';
}

void shuffle<T>(List<T> values, Lcg rng) {
  for (var i = values.length - 1; i > 0; i--) {
    final j = rng.index(i + 1), saved = values[i];
    values[i] = values[j];
    values[j] = saved;
  }
}

List<Json> cognitiveTargets(String taskId, Json task, int level, Lcg rng) {
  final targets = <Json>[];
  if (taskId == 'G2_INHIBITION') {
    var types = <String>[];
    for (var retry = 0; retry < task['shuffle_retry_limit']; retry++) {
      types = [
        ...List<String>.filled(task['go_count'], 'GO'),
        ...List<String>.filled(task['no_go_count'], 'NO_GO'),
      ];
      shuffle(types, rng);
      var run = 0;
      var valid = true;
      for (final type in types) {
        run = type == 'NO_GO' ? run + 1 : 0;
        if (run > task['maximum_consecutive_no_go']) valid = false;
      }
      if (valid) break;
      types = [];
    }
    if (types.isEmpty) {
      types = [
        'GO',
        'GO',
        'NO_GO',
        'GO',
        'GO',
        'NO_GO',
        'GO',
        'GO',
        'NO_GO',
        'GO',
        'GO',
        'GO',
      ];
    }
    final keys = [0, 0, 0, 1, 1, 1, 2, 2, 2];
    shuffle(keys, rng);
    var go = 0;
    for (var i = 0; i < types.length; i++) {
      final key = types[i] == 'GO' ? keys[go++] : null;
      targets.add({
        'schema_version': 1,
        'logical_index': i,
        'trial_type': types[i],
        'expected_keys': key == null ? <int>[] : [key],
        'target_key': key,
        'rule_id': null,
        'target_time_us': null,
      });
    }
  } else {
    final pairs = <({int r, int s})>[];
    for (var repeat = 0; repeat < task['legal_pair_repetitions']; repeat++) {
      for (var r = 0; r < 3; r++) {
        for (var s = 0; s < 3; s++) {
          if (r != s) pairs.add((r: r, s: s));
        }
      }
    }
    shuffle(pairs, rng);
    final run = task['run_length_by_level'][level - 1] as int;
    String? previous;
    for (var i = 0; i < pairs.length; i++) {
      final rule = (i ~/ run).isEven ? 'POSITION' : 'SHAPE';
      final key = rule == 'POSITION' ? pairs[i].r : pairs[i].s;
      targets.add({
        'schema_version': 1,
        'logical_index': i,
        'trial_type': 'GO',
        'expected_keys': [key],
        'target_key': key,
        'rule_id': rule,
        'target_time_us': null,
        'r': pairs[i].r,
        's': pairs[i].s,
        'switch_flag': i == 0 ? null : rule != previous,
      });
      previous = rule;
    }
  }
  return targets;
}

String windowOutcome(
  Json target,
  int actions,
  List<int> consumed,
  int invalid,
) {
  if (target['trial_type'] == 'NO_GO') {
    return actions == 0 ? 'CORRECT_WITHHOLD' : 'COMMISSION';
  }
  if (actions == 0) return 'OMISSION';
  if (consumed.isEmpty || consumed.first != target['target_key']) {
    return 'WRONG_KEY';
  }
  return actions == 1 && invalid == 0 ? 'HIT' : 'EXTRA_RESPONSE';
}
