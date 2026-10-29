import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/record_contract.dart';
import 'package:piano_practice/domain/cognitive_tasks.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'task_engine_test.dart' show create, ready;
import 'record_metrics_test.dart' show capture, validate;
import 'live_clock_regression_test.dart' show AdvancingClock;

void closeWindow(TaskEngine e, ManualClock clock) {
  clock.now += e.responseWindowUs;
  e.tick();
}

void goTrial(TaskEngine e, ManualClock clock) {
  while (true) {
    ready(e, clock);
    if (e.target['trial_type'] == 'GO') return;
    closeWindow(e, clock);
  }
}

Json lastResult(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;

void main() {
  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    test(
      '$task one microsecond before the end stays inside on a live clock',
      () {
        final clock = AdvancingClock();
        final e = TaskEngine(
          config: create(ManualClock()).config,
          clock: clock,
          taskId: task,
          mode: 'ASSIST',
          level: 1,
          song: [],
          seed: 47,
        );
        while (true) {
          for (var i = 0; i < 2500 && e.phase != 'response'; i++) {
            clock.time += 20000;
            e.tick();
            if (e.phase == 'cue') e.cuePresented();
          }
          if (e.target['trial_type'] == 'GO') break;
          clock.time += e.responseWindowUs;
          e.tick();
        }
        clock.time =
            e.base +
            (e.attempts.last['cue_anchor_us'] as int) +
            e.responseWindowUs -
            1;
        e.down(1, e.expected.single);
        e.up(1);
        expect(lastResult(e)['outcome'], 'HIT');
        expect(lastResult(e)['rt_us'], e.responseWindowUs - 1);
        validate(e, capture(e));
      },
    );
    test(
      '$task lowering replaces unfinished targets with matching effective parameters',
      () {
        final clock = ManualClock();
        final e = create(clock, task: task, level: 3);
        ready(e, clock);
        if (e.target['trial_type'] == 'GO') {
          e.down(1, e.expected.single);
          e.up(1);
        }
        closeWindow(e, clock);
        e.pause('USER');
        e.lower();
        expect(e.level, 2);
        expect(e.blocks.first['status'], 'PARTIAL_MANUAL');
        expect(e.block['parameters']['level'], 2);
        expect(
          e.block['parameters'][task == 'G2_INHIBITION'
              ? 'response_window_ms'
              : 'run_length'],
          task == 'G2_INHIBITION' ? 3500 : 4,
        );
        validate(e, {...capture(e), 'decisions': e.decisions});
      },
    );
  }
  test(
    'G3 displays the preceding rule during interval and the new rule at header',
    () {
      final clock = ManualClock(),
          e = create(ManualClock(), task: 'G3_SWITCH', level: 5);
      final time = e.clock as ManualClock;
      ready(e, time);
      closeWindow(e, time);
      expect(e.displayedRule, 'POSITION');
      expect(e.target['rule_id'], 'SHAPE');
      time.now += 700000;
      e.tick();
      expect(e.phase, 'ruleHeader');
      expect(e.displayedRule, 'SHAPE');
      expect(clock.now, 0);
    },
  );
  test(
    'both modes keep configured windows and G3 changes only its run length',
    () {
      final config = create(ManualClock()).config;
      for (final mode in ['ASSIST', 'CHALLENGE']) {
        for (var level = 1; level <= 5; level++) {
          final g2 = TaskEngine(
            config: config,
            clock: ManualClock(),
            taskId: 'G2_INHIBITION',
            mode: mode,
            level: level,
            song: [],
          );
          final g3 = TaskEngine(
            config: config,
            clock: ManualClock(),
            taskId: 'G3_SWITCH',
            mode: mode,
            level: level,
            song: [],
          );
          expect(
            g2.responseWindowUs,
            (mode == 'ASSIST'
                    ? [4000, 3500, 3000, 2500, 2000]
                    : [3000, 2750, 2500, 2250, 2000])[level - 1] *
                1000,
          );
          expect(g3.responseWindowUs, mode == 'ASSIST' ? 3500000 : 2750000);
          expect(g3.parameters['run_length'], [6, 4, 3, 2, 1][level - 1]);
        }
      }
    },
  );
  test(
    'G2 generation is deterministic, balanced and bounded for 100 seeds',
    () {
      final config = create(ManualClock()).config;
      for (var seed = 1; seed <= 100; seed++) {
        final first = cognitiveTargets(
          'G2_INHIBITION',
          config.task('G2_INHIBITION'),
          1,
          Lcg(seed),
        );
        expect(
          canonical(first),
          canonical(
            cognitiveTargets(
              'G2_INHIBITION',
              config.task('G2_INHIBITION'),
              1,
              Lcg(seed),
            ),
          ),
        );
        expect(first.where((t) => t['trial_type'] == 'GO'), hasLength(9));
        expect(first.where((t) => t['trial_type'] == 'NO_GO'), hasLength(3));
        for (var key = 0; key < 3; key++) {
          expect(first.where((t) => t['target_key'] == key), hasLength(3));
        }
        var run = 0;
        for (final t in first) {
          run = t['trial_type'] == 'NO_GO' ? run + 1 : 0;
          expect(run, lessThanOrEqualTo(2));
        }
      }
      final task = {...config.task('G2_INHIBITION'), 'shuffle_retry_limit': 0};
      expect(
        cognitiveTargets(
          'G2_INHIBITION',
          task,
          1,
          Lcg(1),
        ).map((t) => t['trial_type']).toList(),
        [
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
        ],
      );
    },
  );
  for (var level = 1; level <= 5; level++) {
    test('G3 all ordered pairs twice and fixed rule runs at level $level', () {
      final e = create(ManualClock(), task: 'G3_SWITCH', level: level);
      final targets = (e.block['targets']['trials'] as List).cast<Json>();
      final run = [6, 4, 3, 2, 1][level - 1];
      expect(targets.first['switch_flag'], isNull);
      for (var r = 0; r < 3; r++) {
        for (var s = 0; s < 3; s++) {
          if (r != s) {
            expect(
              targets.where((t) => t['r'] == r && t['s'] == s),
              hasLength(2),
            );
          }
        }
      }
      for (var i = 0; i < 12; i++) {
        expect(targets[i]['rule_id'], (i ~/ run).isEven ? 'POSITION' : 'SHAPE');
        expect(
          targets[i]['target_key'],
          targets[i][(i ~/ run).isEven ? 'r' : 's'],
        );
        if (i > 0) expect(targets[i]['switch_flag'], i % run == 0);
      }
      validate(e, capture(e));
    });
  }
  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    for (final scenario in [
      'HIT',
      'OMISSION',
      'WRONG_KEY',
      'EXTRA_RESPONSE',
      'OUTSIDE',
    ]) {
      test('$task full window and $scenario result', () {
        final clock = ManualClock(), e = create(ManualClock(), task: task);
        final time = e.clock as ManualClock;
        goTrial(e, time);
        final validBefore = e.completed, expected = e.expected.single;
        if (scenario == 'WRONG_KEY') {
          e.down(1, (expected + 1) % 3);
          e.up(1);
        }
        if (scenario == 'OUTSIDE') {
          e.down(1, null);
          e.up(1);
        }
        if (scenario != 'OMISSION') {
          time.now += 100000;
          e.down(1, expected);
          e.up(1);
        }
        if (scenario == 'EXTRA_RESPONSE') {
          e.down(1, expected);
          e.up(1);
        }
        expect(e.completed, validBefore);
        expect(e.phase, 'response');
        closeWindow(e, time);
        final r = lastResult(e);
        expect(
          r['outcome'],
          scenario == 'OUTSIDE' ? 'EXTRA_RESPONSE' : scenario,
        );
        expect(r['rt_us'], scenario == 'HIT' ? 100000 : null);
        expect(r['active_duration_us'], e.responseWindowUs);
        validate(e, capture(e));
        expect(clock.now, 0);
      });
    }
    test('$task window end is exclusive and interval input is unassigned', () {
      final clock = ManualClock(), e = create(ManualClock(), task: task);
      final time = e.clock as ManualClock;
      goTrial(e, time);
      time.now =
          e.base +
          (e.attempts.last['cue_anchor_us'] as int) +
          e.responseWindowUs;
      e.down(1, e.expected.single);
      e.up(1);
      expect(lastResult(e)['outcome'], 'OMISSION');
      final press = e.events.lastWhere((v) => v['kind'] == 'INTERTRIAL_PRESS');
      expect(press['trial_id'], isNull);
      expect(press['attempt_id'], isNull);
      validate(e, capture(e));
      expect(clock.now, 0);
    });
    test('$task pause freezes window and retains target and attempt', () {
      final e = create(ManualClock(), task: task), time = ManualClock();
      final clock = e.clock as ManualClock;
      goTrial(e, clock);
      final target = canonical(e.target),
          attempt = e.attempts.last['attempt_id'];
      clock.now += 100000;
      e.pause('USER');
      clock.now += 9000000;
      e.resume();
      expect(e.attempts.last['attempt_id'], attempt);
      expect(canonical(e.target), target);
      e.down(1, e.expected.single);
      e.up(1);
      closeWindow(e, clock);
      final r = lastResult(e);
      expect(r['outcome'], 'HIT');
      expect(r['rt_us'], 100000);
      expect(r['paused_duration_us'], 9000000);
      expect(r['active_duration_us'], e.responseWindowUs);
      expect(r['assisted'], true);
      expect(
        e.events.where(
          (v) =>
              v['kind'] == 'AUDIO_REQUEST' && v['payload']['owner'] == 'DEMO',
        ),
        isEmpty,
      );
      validate(e, capture(e));
      expect(time.now, 0);
    });
    test(
      '$task two blocks commit and validate, help retry keeps the same stimulus',
      () {
        final clock = ManualClock(), e = create(ManualClock(), task: task);
        final time = e.clock as ManualClock;
        ready(e, time);
        final target = canonical(e.target);
        e.pause('INTERRUPTED_BACKGROUND');
        e.resume(help: true);
        ready(e, time);
        expect(canonical(e.target), target);
        for (var block = 0; block < 2; block++) {
          for (var trial = 0; trial < 12; trial++) {
            if (e.phase != 'response') ready(e, time);
            if (e.target['trial_type'] == 'GO') {
              e.down(1, e.expected.single);
              e.up(1);
            }
            closeWindow(e, time);
          }
          if (block == 0) e.nextBlock();
        }
        expect(e.completed, 24);
        expect(e.finishStatus, 'COMPLETED');
        validate(e, {...capture(e), 'decisions': e.decisions});
        expect(e.summary()['sample_counts']['valid'], 24);
        expect(
          e.attempts.where((a) => a['validity'] == 'INTERRUPTED'),
          hasLength(1),
        );
        expect(clock.now, 0);
      },
    );
  }
  test('G2 no-go counts blank, disabled and key presses as commissions', () {
    for (final action in ['none', 'key', 'outside', 'disabled']) {
      final e = create(ManualClock(), task: 'G2_INHIBITION'),
          clock = ManualClock();
      final time = e.clock as ManualClock;
      while (true) {
        ready(e, time);
        if (e.target['trial_type'] == 'NO_GO') break;
        closeWindow(e, time);
      }
      if (action != 'none') {
        e.down(
          1,
          action == 'outside'
              ? null
              : action == 'disabled'
              ? 4
              : 0,
          disabled: action == 'disabled',
        );
        e.up(1);
      }
      closeWindow(e, time);
      expect(
        lastResult(e)['outcome'],
        action == 'none' ? 'CORRECT_WITHHOLD' : 'COMMISSION',
      );
      expect(lastResult(e)['rt_us'], isNull);
      validate(e, capture(e));
      expect(clock.now, 0);
    }
  });
  test('holding a key cannot shorten a window or carry into the next cue', () {
    final e = create(ManualClock(), task: 'G2_INHIBITION');
    final clock = e.clock as ManualClock;
    goTrial(e, clock);
    e.down(1, e.expected.single);
    closeWindow(e, clock);
    expect(lastResult(e)['outcome'], 'HIT');
    clock.now += 700000;
    e.tick();
    expect(e.phase, 'intertrial');
    e.up(1);
    clock.now += 299000;
    e.tick();
    expect(e.phase, 'intertrial');
    clock.now += 21000;
    e.tick();
    expect(e.phase, 'cue');
  });
  test(
    'G3 first header and switching header are unscored and wait for release',
    () {
      final e = create(ManualClock(), task: 'G3_SWITCH');
      final clock = e.clock as ManualClock;
      while (e.phase != 'ruleHeader') {
        clock.now += 20000;
        e.tick();
      }
      final start = clock.now;
      e.down(1, 0);
      clock.now = start + 1500000;
      e.tick();
      expect(e.phase, 'ruleHeader');
      e.up(1);
      clock.now += 320000;
      e.tick();
      expect(e.phase, 'cue');
      e.cuePresented();
      closeWindow(e, clock);
      expect(lastResult(e)['outcome'], 'OMISSION');
    },
  );
  test(
    'G2 all waits must not inflate GO performance, and two commissions are LOW',
    () {
      final e = create(ManualClock(), task: 'G2_INHIBITION', level: 3);
      final clock = e.clock as ManualClock;
      for (var i = 0; i < 12; i++) {
        ready(e, clock);
        closeWindow(e, clock);
      }
      expect(e.summary()['rates']['primary'], {
        'numerator': 0,
        'denominator': 9,
      });
      expect(e.summary()['rates']['no_go_commission'], {
        'numerator': 0,
        'denominator': 3,
      });
      expect(e.decisions.single['action'], 'DOWN');
      final rows = [
        ...List.generate(
          9,
          (_) => {
            'trial_type': 'GO',
            'outcome': 'HIT',
            'help_count': 0,
            'interrupted_retry_count': 0,
          },
        ),
        ...List.generate(
          3,
          (i) => {
            'trial_type': 'NO_GO',
            'outcome': i < 2 ? 'COMMISSION' : 'CORRECT_WITHHOLD',
            'help_count': 0,
            'interrupted_retry_count': 0,
          },
        ),
      ];
      expect(
        AdaptivePolicy(e.config, e.taskId).evaluate(3, rows).action,
        'DOWN',
      );
    },
  );
  test('G3 11/12 with B 3/4 is not HIGH; two perfect groups promote once', () {
    final e = create(ManualClock(), task: 'G3_SWITCH', level: 2);
    final rows = List<Json>.generate(
      12,
      (i) => {
        'rule_id': i < 8 ? 'POSITION' : 'SHAPE',
        'outcome': i == 11 ? 'WRONG_KEY' : 'HIT',
        'help_count': 0,
        'interrupted_retry_count': 0,
      },
    );
    final policy = AdaptivePolicy(e.config, e.taskId);
    expect(policy.evaluate(2, rows).action, 'HOLD');
    expect(policy.highStreak, 0);
    rows.last['outcome'] = 'HIT';
    expect(policy.evaluate(2, rows).action, 'HOLD');
    expect(policy.evaluate(2, rows).after, 3);
  });
  test('G3 switch median difference needs five unassisted HIT samples in both groups', () {
    Json summary(int switchCount, int repeatCount) => PracticeMetrics.build(
      taskId: 'G3_SWITCH',
      version: 'metrics',
      trials: [],
      events: [],
      planned: 12,
      complete: true,
      attempts: [
        for (var i = 0; i < switchCount + repeatCount; i++)
          {
            'validity': 'VALID',
            'attempt_id': '$i',
            'result': {
              'outcome': 'HIT',
              'trial_type': 'GO',
              'rule_id': 'POSITION',
              'switch_flag': i < switchCount,
              'rt_us': i < switchCount ? 200000 : 100000,
              'assisted': false,
              'response_action_count': 1,
              'active_duration_us': 3500000,
              'outside_count': 0,
              'disabled_count': 0,
              'overlap_count': 0,
              'extra_count': 0,
            },
          },
      ],
    );
    expect(summary(4, 5)['switch_median_difference'], isNull);
    expect(summary(5, 5)['switch_median_difference'], {
      'numerator_us': 100000,
      'denominator': 1,
    });
  });
  test('window result validation rejects tampered outcome, RT and shape', () {
    final e = create(ManualClock(), task: 'G3_SWITCH');
    final clock = e.clock as ManualClock;
    ready(e, clock);
    e.down(1, e.expected.single);
    e.up(1);
    closeWindow(e, clock);
    final original = lastResult(e);
    RecordContract.result(original, e.taskId);
    for (final change in [
      {'outcome': 'OMISSION'},
      {'rt_us': null},
      {'r': original['s']},
    ]) {
      expect(
        () => RecordContract.result({...original, ...change}, e.taskId),
        throwsFormatException,
      );
    }
  });
}
