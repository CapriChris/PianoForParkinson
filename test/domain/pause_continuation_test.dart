import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';

import 'task_engine_test.dart' show create, ready, play;
import 'record_metrics_test.dart' show capture, validate;

void main() {
  test('S1 delayed highlight also freezes during user pause', () {
    final c = ManualClock(), e = create(c, task: 'S1_GUIDED', level: 2);
    ready(e, c);
    expect(e.trial['policy_hint_count'], 0);
    e.pause('USER');
    c.now += 60000000;
    e.resume();
    e.tick();
    expect(e.trial['policy_hint_count'], 0);
    c.now += 2000000;
    e.tick();
    expect(e.trial['policy_hint_count'], 1);
  });
  test('G1 pause retains consumed keys, attempt and remaining window without demo replay', () {
    final c = ManualClock(), e = create(c);
    ready(e, c);
    final expected = List<int>.from(e.expected);
    final attempt = e.attempts.last['attempt_id'];
    final demos = e.audio.where((a) => a['kind'] == 'demo').length;
    e.down(1, expected.first);
    c.now += 10000;
    e.up(1);
    e.pause('USER');
    c.now += 60000000;
    e.tick();
    e.resume();
    expect(e.phase, 'response');
    expect(e.attempts.last['attempt_id'], attempt);
    expect(e.attempts, hasLength(1));
    expect(e.audio.where((a) => a['kind'] == 'demo').length, demos);
    play(e, c, expected.skip(1).toList());
    final r = e.attempts.first['result'];
    expect(r['full_correct'], true);
    expect(r['consumed_keys'], expected);
    expect(r['paused_duration_us'], 60000000);
    expect(r['active_duration_us'], lessThan(1000000));
    expect(r['interrupted_retry_count'], 0);
    expect(r['user_pause_count'], 1);
    expect(e.policy.upgradeAllowed, false);
    validate(e, capture(e));
  });
  test('first response statistics exclude a pause before the first key', () {
    final c = ManualClock(), e = create(c);
    ready(e, c);
    c.now += 100000;
    e.pause('USER');
    c.now += 70000000;
    e.resume();
    play(e, c, List<int>.from(e.expected));
    expect(e.summary()['timing_groups']['first_response']['sum_us'], 100000);
    validate(e, capture(e));
  });
  test('S1 wrong press is retained across pause and continue', () {
    final c = ManualClock(), e = create(c, task: 'S1_GUIDED');
    ready(e, c);
    e.down(1, 1);
    e.up(1);
    e.pause('USER');
    c.now += 30000000;
    e.resume();
    expect(e.phase, 'response');
    play(e, c, [0]);
    expect(e.attempts.first['result']['first_pass'], false);
    expect(e.attempts.first['result']['wrong_press_count'], 1);
    expect(e.attempts.first['result']['response_action_count'], 2);
    validate(e, capture(e));
  });
  test('a demo continues with the next note instead of restarting', () {
    final c = ManualClock(), e = create(c);
    for (var i = 0; i < 300 && e.phase != 'demo'; i++) {
      c.now += 20000;
      e.tick();
    }
    expect(e.audio.where((a) => a['kind'] == 'demo').length, 1);
    e.pause('USER');
    c.now += 30000000;
    e.tick();
    e.resume();
    expect(e.phase, 'demo');
    expect(e.audio.where((a) => a['kind'] == 'demo').length, 1);
    c.now += 900000;
    e.tick();
    expect(e.audio.where((a) => a['kind'] == 'demo').length, 2);
    ready(e, c);
    play(e, c, List<int>.from(e.expected));
    expect(
      e.summary()['timing_groups']['first_response']['sum_us'],
      greaterThanOrEqualTo(0),
    );
    validate(e, capture(e));
  });
  test('explicit help after suspension restarts an assisted attempt', () {
    final c = ManualClock(), e = create(c);
    ready(e, c);
    e.pause('USER');
    e.resume(help: true);
    ready(e, c);
    expect(e.attempts.first['validity'], 'INTERRUPTED');
    expect(e.attempts, hasLength(2));
    play(e, c, List<int>.from(e.expected));
    expect(e.attempts.last['result']['help_count'], 1);
    validate(e, capture(e));
  });
  test(
    'exit while suspended closes the retained attempt without scoring it',
    () {
      final c = ManualClock(), e = create(c);
      ready(e, c);
      e.pause('USER');
      c.now += 60000000;
      e.finish('EXITED');
      expect(e.attempts.first['validity'], 'INTERRUPTED');
      expect(e.attempts.first['active_duration_us'], 0);
      expect(e.summary()['rates']['primary']['denominator'], 0);
      validate(e, capture(e));
    },
  );
}
