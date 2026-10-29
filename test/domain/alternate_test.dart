import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'responsive_controls_test.dart' show advanceTo;
import 'task_engine_test.dart' show ready;
import 'record_metrics_test.dart' show capture, validate;

TaskEngine alternate(ManualClock c, {int level = 1}) => TaskEngine(
  config: PracticeConfig(
    jsonDecode(File('assets/config/demo.json').readAsStringSync()) as Json,
  ),
  clock: c,
  taskId: 'M1_ALTERNATE',
  mode: 'ASSIST',
  level: level,
  song: [4, 4, 4],
  seed: 47,
);
Json lastResult(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;
void answer(
  TaskEngine e,
  ManualClock c, {
  int? key,
  int duration = 400000,
  int error = 0,
}) {
  ready(e, c);
  final beat = e.base + e.scheduledBeatUs;
  c.now = beat + error;
  e.down(1, key ?? e.expected.single);
  c.now += duration;
  e.up(1);
  advanceTo(e, c, beat + e.beatAfterUs + 1);
  if (e.finishingPhrase) advanceTo(e, c, e.base + e.phraseEndUs);
}

void main() {
  for (var level = 1; level <= 4; level++) {
    test(
      'M1 level $level generates two alternating 12-target blocks and seals all scores',
      () {
        final c = ManualClock(), e = alternate(c, level: level);
        expect(e.song, List.generate(12, (i) => i % 2));
        expect(e.trialCount, 12);
        expect(e.planned, 24);
        for (var block = 0; block < 2; block++) {
          final bpm = [40, 45, 50, 55][level - 1];
          final targets = e.block['targets']['trials'] as List;
          for (var i = 0; i < 12; i++) {
            expect(targets[i]['expected_keys'], [i % 2]);
            expect(targets[i]['target_time_us'], 1000000 + i * 60000000 ~/ bpm);
            answer(e, c);
          }
          expect(e.block['valid_trial_count'], 12);
          if (block == 0) {
            expect(e.phase, 'feedback');
            e.nextBlock();
          }
        }
        expect(e.ended, true);
        expect(e.summary()['rates']['primary'], {
          'numerator': 24,
          'denominator': 24,
        });
        expect(
          e.summary()['timing_groups']['alternate_hit_interval']['samples'],
          22,
        );
        expect(e.summary()['active_duration_us'], 19200000);
        expect(e.level, (level + 1).clamp(1, 4));
        validate(e, capture(e));
      },
    );
  }
  for (final outcome in [
    'OMISSION',
    'WRONG_KEY',
    'TOO_SHORT',
    'EXTRA_RESPONSE',
    'OUTSIDE',
    'OVERLAP',
  ]) {
    test('M1 $outcome is recorded without borrowing the next target', () {
      final c = ManualClock(), e = alternate(c);
      ready(e, c);
      final beat = e.base + e.scheduledBeatUs;
      c.now = beat;
      final key = e.expected.single;
      if (outcome != 'OMISSION') {
        e.down(
          1,
          outcome == 'OUTSIDE'
              ? null
              : outcome == 'WRONG_KEY'
              ? 1 - key
              : key,
        );
        if (outcome == 'OVERLAP') e.down(2, 1 - key);
        c.now += outcome == 'TOO_SHORT' ? 100000 : 200000;
        e.up(1);
        if (outcome == 'EXTRA_RESPONSE') {
          e.down(2, key);
          e.up(2);
        }
        if (outcome == 'OVERLAP') e.up(2);
      }
      advanceTo(e, c, beat + 400000);
      expect(
        lastResult(e)['outcome'],
        ['OUTSIDE', 'OVERLAP'].contains(outcome)
            ? outcome == 'OUTSIDE'
                  ? 'WRONG_KEY'
                  : 'EXTRA_RESPONSE'
            : outcome,
      );
      expect(e.completed, 1);
      expect(e.expected, [1]);
      expect(lastResult(e)['beat_error_us'], isNull);
      validate(e, capture(e));
    });
  }
  for (final error in [-400000, -200000, 0, 200000]) {
    test(
      'M1 hit at $error us has complete duration and planned beat error',
      () {
        final c = ManualClock(), e = alternate(c);
        answer(e, c, error: error);
        expect(lastResult(e)['outcome'], 'HIT');
        expect(lastResult(e)['beat_error_us'], error);
        expect(lastResult(e)['active_duration_us'], 800000);
        validate(e, capture(e));
      },
    );
  }
  test(
    'M1 pause freezes hold, target, progress and attempt without replay',
    () {
      final c = ManualClock(), e = alternate(c);
      ready(e, c);
      advanceTo(e, c, e.base + e.scheduledBeatUs);
      final id = e.attempts.last['attempt_id'];
      final demos = e.audio.where((a) => a['kind'] == 'demo').length;
      e.down(1, 0);
      c.now += 200000;
      final progress = e.phraseProgress;
      e.pause('USER');
      c.now += 5000000;
      expect(e.phraseProgress, progress);
      expect(e.durationGuide, isNull);
      e.resume();
      expect(e.durationGuide!.progress, .5);
      c.now += 200000;
      e.up(1);
      expect(
        e.attempts.firstWhere((a) => a['validity'] == 'VALID')['attempt_id'],
        id,
      );
      expect(e.audio.where((a) => a['kind'] == 'demo').length, demos);
      expect(lastResult(e)['outcome'], 'HIT');
      validate(e, capture(e));
    },
  );
  test(
    'M1 replay repeats four demo prep beats and the same alternating phrase',
    () {
      final c = ManualClock(), e = alternate(c);
      ready(e, c);
      final targets = canonical(e.block['targets']);
      e.pause('USER');
      e.resume(replay: true);
      ready(e, c);
      expect(canonical(e.block['targets']), targets);
      expect(
        e.events.where(
          (v) =>
              v['kind'] == 'METRONOME_TICK' &&
              v['payload']['owner'] == 'DEMO_LEAD_IN',
        ),
        hasLength(8),
      );
      expect(e.audio.where((a) => a['kind'] == 'demo'), hasLength(24));
      expect(e.showAnswer, false);
      validate(e, capture(e));
    },
  );
  test(
    'M1 intervals break at a miss and never cross blocks or assisted targets',
    () {
      final c = ManualClock(), e = alternate(c);
      answer(e, c);
      answer(e, c);
      answer(e, c, key: 1); // third target is 0
      answer(e, c);
      answer(e, c);
      expect(
        e.summary()['timing_groups']['alternate_hit_interval']['samples'],
        2,
      );
      ready(e, c);
      e.pause('USER');
      e.resume();
      answer(e, c);
      answer(e, c);
      expect(
        e.summary()['timing_groups']['alternate_hit_interval']['samples'],
        2,
      );
      expect(
        e.summary()['timing_groups']['alternate_hit_interval']['cv_ppm'],
        isNull,
      );
      validate(e, capture(e));
    },
  );
  test('M1 interval statistics are stable if SQLite rows arrive in a different order', () {
    final c = ManualClock(), e = alternate(c);
    for (var i = 0; i < 12; i++) {
      answer(e, c);
    }
    final stats = e.summary()['timing_groups']['alternate_hit_interval'];
    e.attempts.setAll(0, e.attempts.reversed.toList());
    expect(e.summary()['timing_groups']['alternate_hit_interval'], stats);
    expect(stats['samples'], 11);
    expect(stats['cv_ppm'], 0);
  });
  test('M1 corrupted alternation and unsupported pool are rejected', () {
    final c = ManualClock(), e = alternate(c);
    answer(e, c);
    final data = capture(e);
    data['trials'][0]['target']['target_key'] = 1;
    expect(() => validate(e, data), throwsFormatException);
    final bad = jsonDecode(jsonEncode(e.config.json)) as Json;
    bad['tasks']['M1_ALTERNATE']['pool'] = [0, 2];
    expect(() => PracticeConfig(bad), throwsFormatException);
  });
  for (final successes in [10, 11]) {
    test('M1 high streak uses ceil 85 percent: $successes of 12', () {
      final e = alternate(ManualClock());
      final rows = List<Json>.generate(
        12,
        (i) => {
          'outcome': i < successes ? 'HIT' : 'OMISSION',
          'help_count': 0,
          'interrupted_retry_count': 0,
        },
      );
      final policy = AdaptivePolicy(e.config, 'M1_ALTERNATE');
      policy.evaluate(1, rows);
      expect(policy.evaluate(1, rows).action, successes == 11 ? 'UP' : 'HOLD');
    });
  }
  test('M1 three consecutive failures reduce level and outside responses block upgrade', () {
    final e = alternate(ManualClock());
    final rows = List<Json>.generate(
      12,
      (i) => {
        'outcome': i < 3 ? 'OMISSION' : 'HIT',
        'help_count': 0,
        'interrupted_retry_count': 0,
      },
    );
    expect(
      AdaptivePolicy(e.config, 'M1_ALTERNATE').evaluate(2, rows).action,
      'DOWN',
    );
    for (final r in rows) {
      r['outcome'] = 'HIT';
    }
    final p = AdaptivePolicy(e.config, 'M1_ALTERNATE');
    p.evaluate(1, rows, outOfWindow: 2);
    expect(p.evaluate(1, rows, outOfWindow: 2).action, 'HOLD');
  });
}
