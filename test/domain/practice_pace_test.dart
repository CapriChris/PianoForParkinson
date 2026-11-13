import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/practice_pace.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/data/record_integrity.dart';
import 'package:piano_practice/data/record_audit.dart';
import 'package:piano_practice/domain/practice_metrics.dart';

import 'task_engine_test.dart' show ready;
import 'responsive_controls_test.dart' show advanceTo;
import 'record_metrics_test.dart' show capture, validate;

PracticeConfig original() => PracticeConfig(
  jsonDecode(File('assets/config/demo.json').readAsStringSync()) as Json,
);
TaskEngine paced(ManualClock clock, String task, {String pace = 'COMFORT'}) =>
    TaskEngine(
      config: practicePace(original(), pace),
      clock: clock,
      taskId: task,
      mode: 'ASSIST',
      level: 1,
      song: [0, 1],
      seed: 47,
    );

void main() {
  test(
    'standard retains exact profile and comfort is isolated and validated',
    () {
      final base = original(), hash = digest(base.json);
      expect(practicePace(base, 'STANDARD').json, base.json);
      final comfort = practicePace(base, 'COMFORT');
      RecordIntegrity.configuration(comfort.json);
      expect(digest(base.json), hash);
      expect(comfort.json['version'], isNot(base.json['version']));
      expect(comfort.json['pace'], 'COMFORT');
      expect(comfort.timing['trial_gap_ms'], 1500);
      expect(
        comfort.task('G1_MEMORY')['modes']['ASSIST']['demo_onset_interval_ms'],
        1500,
      );
      expect(comfort.task('S1_GUIDED')['demo_onset_interval_ms'], 1500);
      expect(
        paced(
          ManualClock(),
          'G1_MEMORY',
          pace: 'STANDARD',
        ).parameters.containsKey('pace'),
        false,
      );
    },
  );
  test(
    'comfort memory audio/cue onsets really wait 1500ms, hold stays 400ms',
    () {
      final c = ManualClock(), e = paced(ManualClock(), 'G1_MEMORY');
      final clock = e.clock as ManualClock;
      ready(e, clock);
      final demo = e.events
          .where(
            (event) =>
                event['kind'] == 'AUDIO_REQUEST' &&
                event['payload']['owner'] == 'DEMO',
          )
          .toList();
      expect(demo.length, 2);
      expect(demo[1]['offset_us'] - demo[0]['offset_us'], 1500000);
      final cue = e.events.lastWhere(
        (event) => event['kind'] == 'CUE_PRESENTED',
      );
      // The engine requests the cue on the next 20ms frame after the gap.
      expect(
        cue['offset_us'] - demo.last['offset_us'],
        inInclusiveRange(1500000, 1520000),
      );
      expect(e.noteDurationUs, 400000);
      expect(c.now, 0);
    },
  );
  test('comfort dual hand responses keep independent raw timestamps and required pair', () {
    for (final reverse in [false, true]) {
      final e = paced(ManualClock(), 'M2_DUAL_ZONE'), c = ManualClock();
      final clock = e.clock as ManualClock;
      ready(e, clock);
      final pair = e.expected.toList();
      expect(pair[0], lessThan(3));
      expect(pair[1], greaterThanOrEqualTo(3));
      e.down(1, pair[reverse ? 1 : 0]);
      clock.now += 700000;
      e.down(2, pair[reverse ? 0 : 1]);
      clock.now += e.responseRemainingUs!;
      e.tick();
      final result = e.attempts.last['result'] as Json;
      expect(result['gap_us'], 700000);
      expect(result['outcome'], 'HIT');
      expect(result['active_duration_us'], 5000000);
      validate(e, capture(e));
      expect(
        auditRows({
          'table': 'attempts',
          'rows': [
            {
              'validity': 'VALID',
              'task_id': e.taskId,
              'result_json': jsonEncode(result),
              'audit_parameters_json': jsonEncode(e.parameters),
            },
          ],
        }),
        isEmpty,
      );
      expect(c.now, 0);
    }
  });
  test('comfort and standard use distinct comparison groups without changing standard conditions', () {
    String comparison(String pace) {
      final e = paced(ManualClock(), 'G1_MEMORY', pace: pace);
      final block = jsonDecode(canonical(e.block)) as Json;
      block['parameters']['layout_snapshot'] = {'layout_id': 'COMPACT'};
      return PracticeMetrics.comparisonKey(
        {
          'snapshot': {
            'task_id': e.taskId,
            'task_version': '2.1.0',
            'content': null,
            'mode': e.mode,
            'parameter_profile': e.config.json,
            'instruction_locale': 'en',
          },
          'environment': {
            'device_local_id': 'test',
            'clock_source': 'DART_RECEIPT',
            'sound_enabled': false,
            'app_gain_permille': 600,
            'audio_route_category': 'MUTED',
            'layout_version': 1,
          },
        },
        block,
        e.summary(),
      )!;
    }

    expect(comparison('COMFORT'), isNot(comparison('STANDARD')));
    expect(comparison('STANDARD'), comparison('STANDARD'));
  });
  test(
    'comfort real cue window, raw latency, transition and snapshot agree',
    () {
      final clock = ManualClock(), e = paced(ManualClock(), 'G2_INHIBITION');
      final c = e.clock as ManualClock;
      ready(e, c);
      while (e.target['trial_type'] != 'GO') {
        c.now += e.responseWindowUs;
        e.tick();
        ready(e, c);
      }
      expect(e.responseWindowUs, 5000000);
      c.now += 900000;
      e.down(1, e.expected.single);
      c.now += 400000;
      e.up(1);
      final result = e.attempts.last['result'] as Json;
      expect(result['rt_us'], 900000);
      expect(e.parameters['pace'], 'COMFORT');
      expect(e.parameters['trial_gap_ms'], 1500);
      expect(e.parameters['response_window_ms'], 5000);
      final end = c.now;
      advanceTo(e, c, end + 1499999);
      expect(e.phase, 'intertrial');
      advanceTo(e, c, end + 1500000);
      expect(e.phase, anyOf('response', 'cue'));
      validate(e, capture(e));
      expect(clock.now, 0);
    },
  );
  test('comfort rhythm schedules genuine slower beats without changing hold/window', () {
    final e = paced(ManualClock(), 'M1_ALTERNATE');
    expect(e.bpm, 30);
    expect(e.noteDurationUs, 400000);
    expect(e.beatBeforeUs, 400000);
    expect(e.beatAfterUs, 400000);
    final targets = e.block['targets']['trials'] as List;
    expect(
      targets[1]['target_time_us'] - targets[0]['target_time_us'],
      2000000,
    );
    expect(targets[0]['expected_keys'], [0]);
    expect(targets[1]['expected_keys'], [1]);
    validate(e, capture(e));
  });
  test(
    'comfort does not auto-upgrade after two high blocks; standard still does',
    () {
      final results = List<Json>.generate(
        12,
        (_) => {
          'outcome': 'HIT',
          'help_count': 0,
          'interrupted_retry_count': 0,
        },
      );
      final comfort = paced(ManualClock(), 'M1_ALTERNATE');
      comfort.policy.evaluate(1, results);
      expect(comfort.policy.evaluate(1, results).after, 1);
      final standard = paced(ManualClock(), 'M1_ALTERNATE', pace: 'STANDARD');
      standard.policy.evaluate(1, results);
      expect(standard.policy.evaluate(1, results).after, 2);
    },
  );
}
