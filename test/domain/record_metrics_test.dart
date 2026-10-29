import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/record_contract.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'task_engine_test.dart' show create, ready, play;

Json capture(TaskEngine e) => jsonDecode(
  canonical({
    'level': e.level,
    'planned': e.planned,
    'finish': e.finishStatus,
    'blocks': e.blocks,
    'trials': e.trials,
    'attempts': e.attempts,
    'events': e.events,
  }),
) as Json;
void validate(TaskEngine e, Json data) => RecordContract.validate(
  data,
  e.id,
  e.epoch,
  e.taskId,
  e.config.blocks,
  e.config.maximum(e.taskId),
  e.config.json['metric_version'] as String,
);

void main() {
  test('LCG zero intermediate state is valid although initial seed must be nonzero', () {
    final config = create(ManualClock()).config;
    final e = TaskEngine(
      config: config,
      clock: ManualClock(),
      taskId: 'G1_MEMORY',
      mode: 'ASSIST',
      level: 1,
      song: [0, 1],
      seed: 793034826,
    );
    expect(e.block['targets']['rng_state_after'], 0);
    validate(e, capture(e));
  });
  test('long waits cannot overflow into fabricated zero variation', () {
    final stats = timingStatistics(
      List.generate(10, (i) => 4000000000 + i * 100000000),
    );
    expect(stats['sum_squared_us'], isNull);
    expect(stats['quality_flags'], contains('SUM_SQUARED_OVERFLOW'));
    expect(stats['cv_ppm'], greaterThan(0));
    expect(() => canonical(stats), returnsNormally);
  });
  test('integer median and nearest-rank P95 with empty and odd samples', () {
    final empty = timingStatistics([]);
    expect(empty['samples'], 0);
    for (final key in [
      'sum_us',
      'median_numerator_us',
      'median_denominator',
      'p95_us',
      'cv_ppm',
    ]) {
      expect(empty[key], isNull);
    }
    final even = timingStatistics([400, 100, 200, 300]);
    expect(even['median_numerator_us'], 500);
    expect(even['median_denominator'], 2);
    expect(even['p95_us'], 400);
    expect(timingStatistics([300, 100, 200])['median_numerator_us'], 200);
    expect(timingStatistics(List.generate(20, (i) => i + 1))['p95_us'], 19);
  });
  test('CV uses sample deviation and requires ten nonzero mean samples', () {
    expect(timingStatistics(List.filled(9, 100))['cv_ppm'], isNull);
    expect(timingStatistics(List.filled(10, 0))['cv_ppm'], isNull);
    expect(timingStatistics(List.filled(10, 100))['cv_ppm'], 0);
    expect(timingStatistics(List.generate(10, (i) => i + 1))['cv_ppm'], 550482);
  });
  test(
    'first G1 consumed response excludes outside input and splits assistance',
    () {
      final clock = ManualClock(), e = create(ManualClock());
      final c = e.clock as ManualClock;
      ready(e, c);
      e.down(1, null);
      e.up(1);
      c.now += 120000;
      play(e, c, List<int>.from(e.expected));
      final summary = e.summary();
      expect(summary['rates']['primary']['numerator'], 0);
      expect(summary['rates']['position_accuracy'], {
        'numerator': 2,
        'denominator': 2,
      });
      expect(summary['timing_groups']['first_response']['sum_us'], 120000);
      expect(
        summary['timing_groups']['first_response_unassisted']['samples'],
        1,
      );
      expect(summary['timing_groups']['key_hold']['samples'], 2);
      validate(e, capture(e));
      expect(clock.now, 0);
    },
  );
  test(
    'S1 repeated errors affect action accuracy without inflating first pass',
    () {
      final c = ManualClock(), e = create(ManualClock(), task: 'S1_GUIDED');
      final clock = e.clock as ManualClock;
      ready(e, clock);
      e.down(1, 1);
      e.up(1);
      e.down(2, null);
      e.up(2);
      play(e, clock, [0]);
      final s = e.summary();
      expect(s['rates']['primary'], {'numerator': 0, 'denominator': 1});
      expect(s['rates']['correct_actions'], {'numerator': 1, 'denominator': 3});
      expect(s['assistance_counts']['policy_hint'], greaterThanOrEqualTo(1));
      validate(e, capture(e));
      expect(c.now, 0);
    },
  );
  test(
    'strict contract rejects missing fields, numeric strings and unknown enums',
    () {
      final c = ManualClock(), e = create(ManualClock());
      final clock = e.clock as ManualClock;
      ready(e, clock);
      play(e, clock, List<int>.from(e.expected));
      final data = capture(e);
      validate(e, data);
      final result = data['attempts'][0]['result'] as Json;
      result['outside_count'] = '0';
      expect(() => validate(e, data), throwsFormatException);
      result['outside_count'] = 0;
      result.remove('first_down_offset_us');
      expect(() => validate(e, data), throwsFormatException);
      result['first_down_offset_us'] = null;
      data['attempts'][0]['validity'] = 'INTERRUPTED_EXIT';
      expect(() => validate(e, data), throwsFormatException);
      expect(c.now, 0);
    },
  );
  test(
    'strict contract rejects broken input links and incomplete terminal slots',
    () {
      final c = ManualClock(), e = create(c);
      ready(e, c);
      play(e, c, List<int>.from(e.expected));
      var data = capture(e);
      final normalized = (data['events'] as List).cast<Json>().firstWhere(
        (e) => e['kind'] == 'KEY_DOWN',
      );
      normalized['source_event_seq'] = 1;
      expect(() => validate(e, data), throwsFormatException);
      data = capture(e);
      data['finish'] = 'COMPLETED';
      expect(() => validate(e, data), throwsFormatException);
    },
  );
  test(
    'complete, helped, lowered and reconfigured records satisfy invariants',
    () {
      for (final action in ['complete', 'help', 'lower', 'layout']) {
        final c = ManualClock(), e = create(c, level: 2);
        ready(e, c);
        play(e, c, List<int>.from(e.expected));
        if (action == 'help') {
          e.pause('USER');
          e.resume(help: true);
        }
        if (action == 'lower') {
          e.pause('USER');
          e.lower();
        }
        if (action == 'layout') {
          e.reconfigure({'layout_id': 'WIDE'});
          e.resume();
        }
        while (!e.ended) {
          if (e.phase == 'feedback') e.nextBlock();
          ready(e, c);
          play(e, c, List<int>.from(e.expected));
          validate(e, capture(e));
        }
        validate(e, capture(e));
      }
    },
  );
  test('fourth same-code error warns; retries remain interruptions and do not change level', () {
    final c = ManualClock(), e = create(c);
    for (var i = 0; i < 4; i++) {
      ready(e, c);
      e.pause('E_AUDIO_PLAY');
      expect(e.errors.unstable, i >= 3);
      expect(e.sessionStatus, 'PAUSED_ERROR');
      e.resume();
    }
    expect(e.completed, 0);
    expect(e.level, 1);
    expect(e.attempts.every((a) => a['validity'] == 'INTERRUPTED'), true);
    expect(e.summary()['rates']['primary']['denominator'], 0);
    e.pause('USER');
    expect(e.errors.count, 4);
    expect(e.sessionStatus, 'PAUSED');
  });
  test('terminal elapsed time freezes for idempotent final saves', () {
    final c = ManualClock(), e = create(c);
    e.finish('EXITED');
    final ended = e.finishedAt;
    c.now += 1000000;
    expect(e.finishedAt, ended);
    expect(e.now, greaterThan(ended!));
  });
  test(
    'comparison groups exclude snapshot UUID but separate level, gain and help',
    () {
      final c = ManualClock(), e = create(c);
      final content = jsonDecode(
        File('assets/content/song.json').readAsStringSync(),
      ) as Json;
      final session = {
        'snapshot': {
          'task_id': e.taskId,
          'task_version': '1.0.0',
          'content': content,
          'mode': e.mode,
          'parameter_profile': e.config.json,
          'instruction_locale': 'en',
        },
        'environment': {
          'device_local_id': 'device-a',
          'clock_source': 'DART_RECEIPT',
          'sound_enabled': true,
          'app_gain_permille': 600,
          'audio_route_category': 'BUILT_IN',
          'layout_version': 1,
        },
      };
      final b = jsonDecode(canonical(e.block)) as Json;
      b['parameters']['layout_snapshot'] = {
        'snapshot_id': 'a',
        'layout_id': 'COMPACT',
      };
      final s = e.summary();
      String key() => PracticeMetrics.comparisonKey(session, b, s)!;
      final original = key();
      b['parameters']['layout_snapshot']['snapshot_id'] = 'b';
      expect(key(), original);
      b['level'] = 2;
      expect(key(), isNot(original));
      b['level'] = 1;
      session['environment']!['app_gain_permille'] = 300;
      expect(key(), isNot(original));
      session['environment']!['app_gain_permille'] = 600;
      s['assistance_counts']['help'] = 1;
      expect(key(), isNot(original));
    },
  );
}
