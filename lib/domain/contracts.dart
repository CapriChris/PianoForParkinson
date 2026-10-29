import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

typedef Json = Map<String, dynamic>;
const appName = '琴伴';
const appVersion = '0.1.53';
const appBuild = '54';

/// New input is normalized separately; legacy canonical hashes stay unchanged.
Object? normalizeRecordText(Object? value) {
  if (value is String) return unicode.nfc(value);
  if (value is List) return value.map(normalizeRecordText).toList();
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) throw const FormatException('Invalid JSON key');
      final key = unicode.nfc(entry.key as String);
      if (result.containsKey(key)) {
        throw const FormatException('Normalized JSON key collision');
      }
      result[key] = normalizeRecordText(entry.value);
    }
    return result;
  }
  if (value == null || value is int || value is bool) return value;
  throw const FormatException('Persistent JSON requires integer values');
}

String uuid() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String canonical(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: sort(v[k])};
    }
    if (v is List) return v.map(sort).toList();
    if (v is double) {
      throw const FormatException('Persistent JSON requires integers');
    }
    return v;
  }

  return jsonEncode(sort(value));
}

String digest(Object? value) =>
    sha256.convert(utf8.encode(canonical(value))).toString();

abstract interface class Clock {
  int get now;
}

class MonotonicClock implements Clock {
  final Stopwatch watch = Stopwatch()..start();
  @override
  int get now => watch.elapsedMicroseconds;
}

class ManualClock implements Clock {
  @override
  int now = 0;
}

class Lcg {
  Lcg(this.state) {
    if (state < 1 || state > 0xffffffff) throw ArgumentError('Invalid seed');
  }
  int state;
  int index(int length) {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    return (state * length) ~/ 0x100000000;
  }
}

class PracticeConfig {
  PracticeConfig(this.json) {
    if (json['schema_version'] != 1 ||
        json['review_status'] != 'UNREVIEWED' ||
        json['effective_channel'] != 'INTERNAL_DEMO' ||
        json['rng_algorithm'] != 'rng-lcg32-1') {
      throw const FormatException('Unsupported parameter profile');
    }
    final performance = json['performance'];
    if (performance != null &&
        (performance is! Map ||
            performance['hold_policy'] != 'HOLD_400_V1' ||
            performance['hold_duration_ms'] != 400 ||
            performance['rhythm_lead_in_beats'] != 4 ||
            !{
              'metrics-2.0.0',
              'metrics-2.1.0',
            }.contains(json['metric_version']) ||
            performance['interaction_policy'] != null &&
                (performance['interaction_policy'] != 'RESPONSIVE_HOLD_V1' ||
                    json['metric_version'] != 'metrics-2.1.0'))) {
      throw const FormatException('Unsupported hold policy');
    }
    final alternate = json['tasks']?['M1_ALTERNATE'];
    if (alternate is Map &&
        alternate['note_duration_ms'] != null &&
        (canonical(alternate['pool']) != '[0,1]' ||
            alternate['planned_trial_count_per_block'] != 12 ||
            canonical(alternate['bpm_by_level']) != '[40,45,50,55]' ||
            alternate['maximum_level'] != 4 ||
            alternate['note_duration_ms'] != 400 ||
            alternate['window_before_target_ms'] != 400 ||
            alternate['window_after_target_ms'] != 400 ||
            alternate['first_target_delay_ms'] != 1000 ||
            alternate['demo_lead_in_beats'] != 4 ||
            alternate['beat_reference'] != 'PLANNED_BEAT_REFERENCE')) {
      throw const FormatException('Unsupported alternating task');
    }
  }
  final Json json;
  Json task(String id) => Map<String, dynamic>.from(json['tasks'][id] as Map);
  int initial(String id, String mode) =>
      task(id)['modes'][mode]['initial_level'] as int;
  int maximum(String id) => task(id)['maximum_level'] as int;
  int get blocks => json['required_block_slots'] as int;
  int ms(Json source, String key) => (source[key] as int) * 1000;
  Json get input => Map<String, dynamic>.from(json['input']);
  Json get timing => Map<String, dynamic>.from(json['timing']);
}

class Decision {
  const Decision(this.action, this.reason, this.before, this.after);
  final String action, reason;
  final int before, after;
}

class AdaptivePolicy {
  AdaptivePolicy(this.config, this.taskId);
  final PracticeConfig config;
  final String taskId;
  int highStreak = 0;
  bool upgradeAllowed = true;
  static bool success(String task, Json r) => switch (task) {
    'G1_MEMORY' => r['full_correct'] == true,
    'G2_INHIBITION' =>
      r['outcome'] == 'HIT' || r['outcome'] == 'CORRECT_WITHHOLD',
    'G3_SWITCH' ||
    'S2_RHYTHM' ||
    'M1_ALTERNATE' ||
    'M2_DUAL_ZONE' => r['outcome'] == 'HIT',
    _ => r['first_pass'] == true,
  };
  Decision evaluate(int level, List<Json> results, {int outOfWindow = 0}) {
    final successes = results.where((r) => success(taskId, r)).length;
    var consecutive = 0, maximumFailures = 0;
    for (final r in results) {
      consecutive = success(taskId, r) ? 0 : consecutive + 1;
      maximumFailures = max(maximumFailures, consecutive);
    }
    final assisted = results.any(
      (r) =>
          (r['help_count'] as int) > 0 ||
          (r['interrupted_retry_count'] as int) > 0,
    );
    final rules = config.json['adaptive'] as Map;
    final lowRatio = rules['low_success_ratio'] as Map;
    final go = results.where((r) => r['trial_type'] == 'GO').toList();
    final hits = go.where((r) => r['outcome'] == 'HIT').length;
    final commissions = results
        .where((r) => r['outcome'] == 'COMMISSION')
        .length;
    final low =
        (taskId == 'G2_INHIBITION' &&
            (hits * 2 < go.length ||
                commissions >=
                    rules[taskId]['low_no_go_commission_minimum'])) ||
        (taskId != 'G2_INHIBITION' &&
            successes * (lowRatio['denominator'] as int) <
                results.length * (lowRatio['numerator'] as int)) ||
        maximumFailures >= rules['low_consecutive_failures'];
    final high =
        !assisted &&
        (taskId == 'G2_INHIBITION'
            ? hits >= rules[taskId]['high_go_hit_minimum'] && commissions == 0
            : taskId == 'G3_SWITCH'
            ? successes >= rules[taskId]['high_hit_minimum'] &&
                  ['POSITION', 'SHAPE'].every((rule) {
                    final members = results
                        .where((r) => r['rule_id'] == rule)
                        .toList();
                    return members.isNotEmpty &&
                        members.where((r) => r['outcome'] == 'HIT').length *
                                5 >=
                            members.length * 4;
                  })
            : taskId == 'S2_RHYTHM' || taskId == 'M1_ALTERNATE'
            ? successes * rules[taskId]['high_hit_ratio']['denominator'] >=
                      results.length *
                          rules[taskId]['high_hit_ratio']['numerator'] &&
                  outOfWindow <= rules[taskId]['high_out_of_window_maximum']
            : taskId == 'M2_DUAL_ZONE'
            ? successes >= rules[taskId]['high_hit_minimum']
            : taskId == 'G1_MEMORY'
            ? successes >= rules[taskId]['high_full_correct_count']
            : successes *
                      rules[taskId]['high_first_pass_ratio']['denominator'] >=
                  results.length *
                      rules[taskId]['high_first_pass_ratio']['numerator']);
    if (low) {
      highStreak = 0;
      return Decision(
        level > 1 ? 'DOWN' : 'HOLD',
        level > 1 ? 'LOW' : 'AT_MIN',
        level,
        max(1, level - 1),
      );
    }
    if (high && upgradeAllowed) {
      highStreak++;
      if (highStreak >= rules['high_streak_required']) {
        highStreak = 0;
        final next = min(config.maximum(taskId), level + 1);
        return Decision(
          next > level ? 'UP' : 'HOLD',
          next > level ? 'HIGH_STREAK' : 'AT_MAX',
          level,
          next,
        );
      }
    } else {
      highStreak = 0;
    }
    return Decision('HOLD', 'STABLE', level, level);
  }
}
