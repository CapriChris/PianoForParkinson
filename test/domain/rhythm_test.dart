import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/audio_settings.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/data/record_contract.dart';

import 'task_engine_test.dart' show create, ready;
import 'record_metrics_test.dart' show capture, validate;
import 'live_clock_regression_test.dart' show AdvancingClock;

Json last(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;
void close(TaskEngine e, ManualClock c) {
  c.now = e.base + e.scheduledBeatUs + e.beatAfterUs;
  e.tick();
  if (e.phase == 'cue') e.cuePresented();
}

void hit(TaskEngine e, ManualClock c, {int error = 0, int hold = 400000}) {
  c.now = e.base + e.scheduledBeatUs + error;
  e.down(1, e.expected.single);
  c.now += hold;
  e.up(1);
  if (e.phase == 'cue') e.cuePresented();
}

void main() {
  for (var level = 1; level <= 4; level++) {
    test(
      'level $level locks rational BPM targets without drift or overlap',
      () {
        final c = ManualClock(),
            e = create(ManualClock(), task: 'S2_RHYTHM', level: level);
        final clock = e.clock as ManualClock;
        final targets = e.block['targets']['trials'] as List;
        final tempo = [40, 45, 50, 55][level - 1];
        for (var i = 0; i < targets.length; i++) {
          expect(targets[i]['target_time_us'], 1000000 + i * 60000000 ~/ tempo);
          if (i > 0) {
            expect(
              targets[i]['target_time_us'] - targets[i - 1]['target_time_us'],
              greaterThan(800000),
            );
          }
        }
        ready(e, clock);
        expect(
          e.events.indexWhere((v) => v['kind'] == 'AUDIO_REQUEST'),
          lessThan(e.events.indexWhere((v) => v['kind'] == 'BEAT_SCHEDULED')),
        );
        expect(e.audio.where((v) => v['kind'] == 'demo').length, e.song.length);
        final locked = canonical(e.block['targets']);
        for (var i = 0; i < e.song.length; i++) {
          ready(e, clock);
          hit(e, clock, hold: 100000);
          close(e, clock);
        }
        expect(e.phase, 'feedback');
        expect(e.block['active_duration_us'], 800000 * e.song.length);
        expect(canonical(e.block['targets']), locked);
        validate(e, capture(e));
        expect(c.now, 0);
      },
    );
  }
  for (final error in [-400000, -1, 0, 399999]) {
    test('left-closed right-open hit with error $error us', () {
      final c = ManualClock(), e = create(ManualClock(), task: 'S2_RHYTHM');
      final time = e.clock as ManualClock;
      ready(e, time);
      hit(e, time, error: error, hold: 0);
      close(e, time);
      expect(last(e)['outcome'], 'HIT');
      expect(last(e)['beat_error_us'], error);
      expect(last(e)['active_duration_us'], 800000);
      validate(e, capture(e));
      expect(c.now, 0);
    });
  }
  test('end boundary goes to block OUT_OF_WINDOW and leaves omission', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    ready(e, c);
    final end = e.scheduledBeatUs + e.beatAfterUs;
    c.now = end;
    e.down(1, e.expected.single);
    e.up(1);
    expect(last(e)['outcome'], 'OMISSION');
    final outside = e.events.singleWhere((v) => v['kind'] == 'OUT_OF_WINDOW');
    expect(outside['trial_id'], isNull);
    expect(outside['attempt_id'], isNull);
    expect(e.summary()['error_counts']['out_of_window'], 1);
    e.cuePresented();
    validate(e, capture(e));
  });
  test('before window never borrows the nearest target', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    ready(e, c);
    close(e, c);
    c.now = e.scheduledBeatUs - e.beatBeforeUs - 1;
    e.down(1, e.expected.single);
    e.up(1);
    ready(e, c);
    close(e, c);
    expect(last(e)['outcome'], 'OMISSION');
    expect(e.summary()['error_counts']['out_of_window'], 1);
    validate(e, capture(e));
  });
  for (final scenario in [
    'wrong_then_correct',
    'extra',
    'blank',
    'disabled',
    'overlap',
  ]) {
    test('$scenario is recorded without repairing the first response', () {
      final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
      ready(e, c);
      switch (scenario) {
        case 'wrong_then_correct':
          e.down(1, (e.expected.single + 1) % 5);
          e.up(1);
          e.down(1, e.expected.single);
          e.up(1);
        case 'extra':
          e.down(1, e.expected.single);
          e.up(1);
          e.down(1, e.expected.single);
          e.up(1);
        case 'blank':
          e.down(1, null);
          e.up(1);
        case 'disabled':
          e.down(1, 6, disabled: true);
          e.up(1);
        case 'overlap':
          e.down(1, e.expected.single);
          e.down(2, e.expected.single);
          e.up(2);
          e.up(1);
      }
      close(e, c);
      expect(
        last(e)['outcome'],
        ['extra', 'overlap'].contains(scenario)
            ? 'EXTRA_RESPONSE'
            : 'WRONG_KEY',
      );
      expect(last(e)['beat_error_us'], isNull);
      validate(e, capture(e));
    });
  }
  test('a held key does not shift the next window', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    ready(e, c);
    final firstTarget = e.scheduledBeatUs;
    e.down(1, e.expected.single);
    close(e, c);
    final secondTarget = e.scheduledBeatUs;
    expect(secondTarget - firstTarget, 1500000);
    ready(e, c);
    e.down(2, e.expected.single);
    e.up(2);
    e.up(1);
    close(e, c);
    expect(last(e)['overlap_count'], 1);
    expect(last(e)['outcome'], 'WRONG_KEY');
    expect(e.scheduledBeatUs - secondTarget, 1500000);
    validate(e, capture(e));
  });
  for (final afterPress in [false, true]) {
    test(
      'pause ${afterPress ? 'after' : 'before'} DOWN freezes plan, no demo replay',
      () {
        final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
        ready(e, c);
        final attempt = e.attempts.last['attempt_id'];
        final target = e.scheduledBeatUs;
        final table = canonical(e.block['targets']);
        final demoCount = e.audio.where((v) => v['kind'] == 'demo').length;
        if (afterPress) {
          c.now = target - 100000;
          e.down(1, e.expected.single);
          c.now += 200000;
        }
        e.pause('USER');
        final guide = e.durationGuide;
        c.now += 5000000;
        e.tick();
        expect(e.durationGuide, guide);
        e.resume();
        expect(e.attempts.last['attempt_id'], attempt);
        expect(e.scheduledBeatUs, target + 5000000);
        if (afterPress) {
          e.up(1);
        } else {
          hit(e, c, error: 100000, hold: 0);
        }
        close(e, c);
        expect(last(e)['beat_error_us'], afterPress ? -100000 : 100000);
        expect(last(e)['active_duration_us'], 800000);
        expect(canonical(e.block['targets']), table);
        expect(e.audio.where((v) => v['kind'] == 'demo').length, demoCount);
        validate(e, capture(e));
      },
    );
  }
  test(
    'technical retry keeps target and explicitly reanchors remaining plan',
    () {
      final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
      ready(e, c);
      hit(e, c, hold: 0);
      close(e, c);
      ready(e, c);
      final target = canonical(e.target), first = canonical(e.attempts.first);
      e.pause('INTERRUPTED_BACKGROUND');
      e.resume();
      ready(e, c);
      expect(canonical(e.target), target);
      expect(canonical(e.attempts.first), first);
      expect(e.trial['interrupted_retry_count'], 1);
      expect(e.events.where((v) => v['kind'] == 'BEAT_SCHEDULED').length, 2);
      hit(e, c, hold: 0);
      close(e, c);
      validate(e, capture(e));
    },
  );
  test('lowering cancels unfinished block and snapshots the new BPM', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM', level: 3);
    ready(e, c);
    hit(e, c, hold: 0);
    close(e, c);
    e.pause('USER');
    e.lower();
    expect(e.level, 2);
    expect(e.block['parameters']['bpm'], 45);
    expect(e.blocks.first['status'], 'PARTIAL_MANUAL');
    ready(e, c);
    hit(e, c, hold: 0);
    close(e, c);
    validate(e, {...capture(e), 'decisions': e.decisions});
  });
  test('two blocks seal HIT metrics, signed direction and absolute median', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    for (var b = 0; b < 2; b++) {
      for (var i = 0; i < e.song.length; i++) {
        ready(e, c);
        hit(e, c, error: i.isEven ? -100000 : 200000, hold: 0);
        close(e, c);
      }
      if (b == 0) e.nextBlock();
    }
    expect(e.finishStatus, 'COMPLETED');
    expect(e.level, 2);
    final summary = e.summary();
    expect(summary['rates']['primary'], {'numerator': 16, 'denominator': 16});
    expect(summary['beat_direction_counts'], {
      'early': 8,
      'on_target': 0,
      'late': 8,
    });
    expect(summary['timings']['median_numerator_us'], 300000);
    expect(summary['timings']['median_denominator'], 2);
    expect(e.decisions.last['parameters_after']['bpm'], 45);
    validate(e, {...capture(e), 'decisions': e.decisions});
  });
  test('adaptive HIGH rejects too many out-of-window presses and retries', () {
    final cfg = create(ManualClock()).config;
    final rows = List<Json>.generate(
      8,
      (_) => {'outcome': 'HIT', 'help_count': 0, 'interrupted_retry_count': 0},
    );
    final p = AdaptivePolicy(cfg, 'S2_RHYTHM');
    p.evaluate(1, rows, outOfWindow: 2);
    expect(p.highStreak, 0);
    p.evaluate(1, rows, outOfWindow: 1);
    expect(p.highStreak, 1);
    rows.first['interrupted_retry_count'] = 1;
    p.evaluate(1, rows);
    expect(p.highStreak, 0);
    for (var i = 0; i < 3; i++) {
      rows[i]['outcome'] = 'OMISSION';
    }
    expect(p.evaluate(2, rows).after, 1);
  });
  test('rhythm contract rejects corrupt timings and mismatched targets', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    ready(e, c);
    hit(e, c, hold: 0);
    close(e, c);
    final r = {...last(e), 'beat_error_us': 400000};
    expect(() => RecordContract.result(r, e.taskId), throwsFormatException);
    final data = capture(e);
    data['attempts'][0]['result']['target_time_us']++;
    expect(() => validate(e, data), throwsFormatException);
  });
  test('live receipt clock preserves end minus one microsecond', () {
    final clock = AdvancingClock();
    final e = TaskEngine(
      config: create(ManualClock()).config,
      clock: clock,
      taskId: 'S2_RHYTHM',
      mode: 'ASSIST',
      level: 1,
      song: [0, 1],
      seed: 1,
    );
    while (e.phase != 'response') {
      clock.time += 20000;
      e.tick();
      if (e.phase == 'cue') e.cuePresented();
    }
    clock.time = e.base + e.scheduledBeatUs + e.beatAfterUs - 1;
    e.down(1, e.expected.single);
    e.up(1);
    if (e.phase == 'cue') e.cuePresented();
    expect(last(e)['outcome'], 'HIT');
    expect(last(e)['beat_error_us'], 399999);
    validate(e, capture(e));
  });
  test('guides demonstrate G1 duration but never time its memory response', () {
    final c = ManualClock(), e = create(c);
    while (e.phase != 'demo') {
      c.now += 20000;
      e.tick();
    }
    expect(e.durationGuide?.progress, 0);
    c.now += 200000;
    e.tick();
    expect(e.durationGuide?.progress, .5);
    ready(e, c);
    e.down(1, e.expected.first);
    expect(e.durationGuide, isNull);
  });
  test(
    'S1 bar fills and freezes on pause without a hold-time scoring gate',
    () {
      final c = ManualClock(), e = create(c, task: 'S1_GUIDED');
      ready(e, c);
      e.down(1, e.expected.single);
      c.now += 200000;
      e.tick();
      expect(e.durationGuide?.progress, .5);
      e.pause('USER');
      c.now += 5000000;
      expect(e.durationGuide?.progress, .5);
      e.resume();
      expect(e.durationGuide?.progress, .5);
      e.up(1);
      expect(last(e)['first_pass'], true);
    },
  );
  test('legacy default rises once; custom or muted gains are preserved', () {
    expect(
      normalizedAudioSettings({'gain_permille': 600})['gain_permille'],
      850,
    );
    for (final gain in [0, 250, 1000]) {
      expect(
        normalizedAudioSettings({'gain_permille': gain})['gain_permille'],
        gain,
      );
    }
    final explicit = {
      'gain_permille': 600,
      'speech_gain_permille': 200,
      'volume_controls_version': 2,
      'sound_enabled': false,
    };
    expect(normalizedAudioSettings(explicit), explicit);
  });
  test('a repeated target does not inherit a previously held key duration', () {
    final c = ManualClock(),
        e = TaskEngine(
          config: create(ManualClock()).config,
          clock: ManualClock(),
          taskId: 'S2_RHYTHM',
          mode: 'ASSIST',
          level: 1,
          song: [0, 0],
        );
    final time = e.clock as ManualClock;
    ready(e, time);
    e.down(1, 0);
    time.now += 400000;
    e.tick();
    expect(e.durationGuide?.progress, 1);
    close(e, time);
    ready(e, time);
    expect(e.durationGuide?.key, 0);
    expect(e.durationGuide?.progress, 0);
    expect(c.now, 0);
  });
  test('a late cue is invalidated rather than moving the fixed beat plan', () {
    final c = ManualClock(), e = create(c, task: 'S2_RHYTHM');
    ready(e, c);
    final table = canonical(e.block['targets']);
    close(e, c); // close() presents the new cue on time.
    ready(e, c);
    close(e, c);
    e.pause('INTERRUPTED_BACKGROUND');
    e.resume();
    for (var i = 0; i < 2500 && e.phase != 'cue'; i++) {
      c.now += 20000;
      e.tick();
    }
    c.now += 100001;
    e.cuePresented();
    expect(e.phase, 'paused');
    expect(e.pauseReason, 'INVALID_FRAME_LATE');
    expect(e.attempts.last['validity'], 'INVALID');
    expect(e.attempts.last['outcome'], isNull);
    expect(canonical(e.block['targets']), table);
    validate(e, capture(e));
  });
}
