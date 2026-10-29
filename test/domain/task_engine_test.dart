import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

final config = PracticeConfig(
  jsonDecode(File('test/fixtures/demo-0.1.5.json').readAsStringSync()) as Json,
);
TaskEngine create(
  ManualClock clock, {
  String task = 'G1_MEMORY',
  int level = 1,
}) => TaskEngine(
  config: config,
  clock: clock,
  taskId: task,
  mode: 'ASSIST',
  level: level,
  seed: 1,
  song: [0, 1, 2, 4, 2, 1, 0, 0],
);
void ready(TaskEngine e, ManualClock c) {
  for (var i = 0; i < 2500; i++) {
    c.now += 20000;
    e.tick();
    if (e.phase == 'cue') e.cuePresented();
    if (e.phase == 'response') return;
    if (e.phase == 'paused' || e.ended) {
      throw StateError('Cannot reach response: ${e.phase}');
    }
  }
  throw StateError('Response not reached');
}

void play(TaskEngine e, ManualClock c, List<int> keys) {
  for (final key in keys) {
    e.down(1, key);
    c.now += 10000;
    e.up(1);
    c.now += 10000;
  }
  if (e.memory) {
    c.now += 300000;
    e.tick();
  }
}

void main() {
  test('LCG golden state and index, reproducible across instances', () {
    final rng = Lcg(1);
    expect(rng.index(3), 0);
    expect(rng.state, 1015568748);
    expect(rng.index(3), 1);
    expect(rng.state, 1586005467);
    final a = Lcg(47), b = Lcg(47);
    expect(
      List.generate(50, (_) => a.index(3)),
      List.generate(50, (_) => b.index(3)),
    );
  });
  test('A01 positional accuracy differs from full and prefix correctness', () {
    final c = ManualClock(), e = create(ManualClock());
    // Use the injected clock belonging to this engine.
    final clock = e.clock as ManualClock;
    e.trials.first['target']['expected_keys'] = [0, 2, 1];
    ready(e, clock);
    play(e, clock, [0, 1, 1]);
    final result = e.attempts.first['result'] as Json;
    expect(result['position_correct_count'], 2);
    expect(result['longest_correct_prefix'], 1);
    expect(result['full_correct'], false);
    expect(c.now, 0);
  });
  test('A02 repeated keys after UP are distinct responses', () {
    final c = ManualClock(), e = create(ManualClock());
    final clock = e.clock as ManualClock;
    e.trials.first['target']['expected_keys'] = [0, 0];
    ready(e, clock);
    play(e, clock, [0, 0]);
    expect(e.attempts.first['result']['full_correct'], true);
    expect(e.attempts.first['result']['consumed_keys'], [0, 0]);
    expect(c.now, 0);
  });
  test('A03 extra response during tail invalidates full correctness', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    for (final key in e.expected) {
      e.down(1, key);
      e.up(1);
      c.now += 10000;
    }
    e.down(2, 0);
    e.up(2);
    c.now += 300000;
    e.tick();
    expect(e.attempts.first['result']['full_correct'], false);
    expect(e.attempts.first['result']['extra_count'], 1);
  });
  test('A04 timeout keeps omitted positions in valid denominator', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    e.down(1, e.expected.first);
    e.up(1);
    c.now += 5000000;
    e.tick();
    expect(e.attempts.first['validity'], 'VALID');
    expect(e.attempts.first['result']['omitted_position_count'], 1);
    expect(e.attempts.first['outcome'], 'TIMEOUT');
  });
  test(
    'A05 replay retries same target and cannot score interrupted attempt',
    () {
      final c = ManualClock();
      final e = create(c);
      ready(e, c);
      final target = List<int>.from(e.expected);
      e.pause('HELP_REQUESTED');
      e.resume(help: true);
      ready(e, c);
      expect(e.expected, target);
      play(e, c, target);
      expect(e.attempts[0]['validity'], 'INTERRUPTED');
      expect(e.attempts[0]['result'], null);
      expect(e.attempts[1]['validity'], 'VALID');
      expect(e.attempts[1]['result']['assisted'], true);
      expect(e.completed, 1);
    },
  );
  test(
    'A10 event at response end is outside left-closed right-open window',
    () {
      final c = ManualClock();
      final e = create(c);
      ready(e, c);
      c.now += 5000000;
      e.down(1, 0);
      expect(e.attempts.first['outcome'], 'TIMEOUT');
      expect(e.attempts.first['result']['consumed_keys'], isEmpty);
    },
  );
  test('A11 event at response start is inside window', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    e.down(1, e.expected.first);
    expect(e.phase, 'response');
    expect(
      e.events.where((e) => e['kind'] == 'KEY_DOWN').last['payload']['key_id'],
      e.expected.first,
    );
  });
  test('A14 S1 wrong then correct is completed but not first pass', () {
    final c = ManualClock();
    final e = create(c, task: 'S1_GUIDED');
    ready(e, c);
    e.down(1, 1);
    e.up(1);
    e.down(1, 0);
    expect(e.completed, 0);
    e.up(1);
    expect(e.completed, 1);
    expect(e.attempts.first['result']['first_pass'], false);
  });
  test('A15 S1 waits without forced failure', () {
    final c = ManualClock();
    final e = create(c, task: 'S1_GUIDED');
    ready(e, c);
    c.now += 11000000;
    e.tick();
    expect(e.phase, 'response');
    expect(e.completed, 0);
    expect(e.attempts.first['validity'], 'OPEN');
  });
  test('A18 repeated pointer DOWN pauses without duplicate KEY_DOWN', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    e.down(1, 0);
    e.down(1, 0);
    expect(e.phase, 'paused');
    expect(e.pauseReason, 'E_INPUT_PROTOCOL');
    expect(e.events.where((event) => event['kind'] == 'KEY_DOWN').length, 1);
  });
  test('A20 sliding to another key does not generate another response', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    e.down(1, 0);
    e.move(1, {'x_norm': 900000, 'y_norm': 100000});
    expect(e.events.where((event) => event['kind'] == 'KEY_DOWN').length, 1);
  });
  test('A21 CANCEL interrupts without recording a valid failed attempt', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    e.down(1, 0);
    e.up(1, cancel: true);
    expect(e.phase, 'paused');
    expect(e.attempts.first['validity'], 'INTERRUPTED');
    expect(e.completed, 0);
  });
  test('A23 manual lowering replaces cancelled plan and preserves completed record', () {
    final c = ManualClock();
    final e = create(c, level: 2);
    ready(e, c);
    play(e, c, List<int>.from(e.expected));
    e.pause('USER');
    e.lower();
    expect(e.planned, 7);
    expect(e.completed, 1);
    expect(e.level, 1);
    expect(e.blocks.first['status'], 'PARTIAL_MANUAL');
    expect(e.blocks.last['slot_index'], 0);
    expect(e.policy.upgradeAllowed, false);
  });
  test(
    'A25 two complete high groups increase next-session level exactly once',
    () {
      final c = ManualClock();
      final e = create(c);
      for (var block = 0; block < 2; block++) {
        for (var trial = 0; trial < 3; trial++) {
          ready(e, c);
          play(e, c, List<int>.from(e.expected));
        }
        if (block == 0) {
          expect(e.phase, 'feedback');
          expect(e.level, 1);
          e.nextBlock();
        }
      }
      expect(e.finishStatus, 'COMPLETED');
      expect(e.completed, 6);
      expect(e.level, 2);
      expect(e.summary()['rates']['primary'], {
        'numerator': 6,
        'denominator': 6,
      });
    },
  );
  test('empty summary does not create fabricated valid samples', () {
    final e = create(ManualClock());
    e.finish('EXITED');
    expect(e.summary()['rates']['primary']['denominator'], 0);
    expect(e.attempts, isEmpty);
  });
  test('reconfiguration retains successes and replaces remaining targets', () {
    final c = ManualClock();
    final e = create(c);
    ready(e, c);
    play(e, c, List<int>.from(e.expected));
    e.reconfigure({'layout_id': 'WIDE'});
    expect(e.planned, 7);
    expect(e.completed, 1);
    expect(e.phase, 'paused');
    expect(e.blocks.first['status'], 'INTERRUPTED');
    expect(e.policy.upgradeAllowed, false);
  });
  test('assisted group cannot produce HIGH promotion', () {
    final policy = AdaptivePolicy(config, 'G1_MEMORY');
    final rows = List.generate(
      3,
      (_) => <String, dynamic>{
        'full_correct': true,
        'help_count': 1,
        'interrupted_retry_count': 0,
      },
    );
    expect(policy.evaluate(1, rows).action, 'HOLD');
    expect(policy.evaluate(1, rows).after, 1);
  });
}
