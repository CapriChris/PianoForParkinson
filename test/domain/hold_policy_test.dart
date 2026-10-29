import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/domain/audio_settings.dart';

import 'record_metrics_test.dart' show capture, validate;
import 'task_engine_test.dart' show ready;

final current = PracticeConfig(
  jsonDecode(File('test/fixtures/demo-0.1.6.json').readAsStringSync()) as Json,
);
TaskEngine held(ManualClock clock, String task, {int level = 1}) => TaskEngine(
  config: current,
  clock: clock,
  taskId: task,
  mode: 'ASSIST',
  level: level,
  song: [0, 1, 2, 4, 2, 1, 0, 0],
  seed: 47,
);
Json result(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;
void press(TaskEngine e, ManualClock c, int key, int us) {
  e.down(1, key);
  c.now += us;
  e.up(1);
  if (e.phase == 'cue') e.cuePresented();
}

void endWindow(TaskEngine e, ManualClock c) {
  final anchor = e.attempts.last['cue_anchor_us'] as int;
  c.now = e.base + anchor + e.responseWindowUs;
  e.tick();
}

void main() {
  test(
    'hold rule rejects a silently changed duration under the same policy',
    () {
      final altered = jsonDecode(jsonEncode(current.json)) as Json;
      altered['performance']['hold_duration_ms'] = 200;
      expect(() => PracticeConfig(altered), throwsFormatException);
    },
  );
  test(
    'old disabled audio switches become zero sliders without hidden mute',
    () {
      final upgraded = normalizedAudioSettings({
        'gain_permille': 850,
        'speech_gain_permille': 600,
        'sound_enabled': false,
        'speech_enabled': false,
      });
      expect(upgraded['gain_permille'], 0);
      expect(upgraded['speech_gain_permille'], 0);
      expect(upgraded['sound_enabled'], true);
      expect(upgraded['speech_enabled'], true);
      expect(normalizedAudioSettings(upgraded), upgraded);
    },
  );
  test('audio switch upgrade keeps independently enabled gain', () {
    final upgraded = normalizedAudioSettings({
      'gain_permille': 250,
      'speech_gain_permille': 700,
      'sound_enabled': true,
      'speech_enabled': false,
    });
    expect(upgraded['gain_permille'], 250);
    expect(upgraded['speech_gain_permille'], 0);
  });
  for (final task in ['G1_MEMORY', 'S1_GUIDED']) {
    test(
      '$task short press retries the same note and preserves action counts',
      () {
        final c = ManualClock(), e = held(c, task);
        ready(e, c);
        final trial = e.trial['trial_id'];
        final key = e.expected.first;
        press(e, c, key, 100000);
        expect(e.completed, 0);
        expect(e.trial['trial_id'], trial);
        expect(e.phase, 'response');
        expect(e.durationTooShort, true);
        for (final k in List<int>.from(e.expected)) {
          press(e, c, k, 400000);
        }
        if (e.memory) {
          c.now += 300000;
          e.tick();
        }
        expect(e.completed, 1);
        expect(result(e)['short_press_count'], 1);
        expect(result(e)[e.memory ? 'full_correct' : 'first_pass'], false);
        validate(e, capture(e));
      },
    );
    test('$task exact 400 ms succeeds without short presses', () {
      final c = ManualClock(), e = held(c, task);
      ready(e, c);
      for (final k in List<int>.from(e.expected)) {
        press(e, c, k, 400000);
      }
      if (e.memory) {
        c.now += 300000;
        e.tick();
      }
      expect(result(e)['short_press_count'], 0);
      expect(result(e)[e.memory ? 'full_correct' : 'first_pass'], true);
      validate(e, capture(e));
    });
    test('$task pause excludes suspended hold and does not replay', () {
      final c = ManualClock(), e = held(c, task);
      ready(e, c);
      final demos = e.events
          .where(
            (v) =>
                v['kind'] == 'AUDIO_REQUEST' && v['payload']['owner'] == 'DEMO',
          )
          .length;
      e.down(1, e.expected.first);
      c.now += 200000;
      e.pause('USER');
      c.now += 5000000;
      e.resume();
      expect(e.durationGuide!.progress, .5);
      c.now += 200000;
      e.up(1);
      expect(
        e.events
            .where(
              (v) =>
                  v['kind'] == 'AUDIO_REQUEST' &&
                  v['payload']['owner'] == 'DEMO',
            )
            .length,
        demos,
      );
      if (e.memory) {
        for (final k in e.expected.skip(1).toList()) {
          press(e, c, k, 400000);
        }
        c.now += 300000;
        e.tick();
      }
      expect(result(e)['short_press_count'], 0);
      validate(e, capture(e));
    });
  }
  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    for (final duration in [100000, 400000]) {
      test('$task $duration us uses full window and grades duration', () {
        final c = ManualClock(), e = held(c, task);
        ready(e, c);
        while (e.target['trial_type'] == 'NO_GO') {
          endWindow(e, c);
          ready(e, c);
        }
        press(e, c, e.expected.single, duration);
        endWindow(e, c);
        expect(result(e)['outcome'], duration == 400000 ? 'HIT' : 'TOO_SHORT');
        expect(result(e)['short_press_count'], duration == 400000 ? 0 : 1);
        expect(result(e)['rt_us'], duration == 400000 ? isNotNull : isNull);
        expect(e.phase, 'intertrial');
        validate(e, capture(e));
      });
    }
  }
  test('G2 no-go still means no press; no answer bar encourages a press', () {
    final c = ManualClock(), e = held(c, 'G2_INHIBITION');
    ready(e, c);
    while (e.target['trial_type'] != 'NO_GO') {
      endWindow(e, c);
      ready(e, c);
    }
    expect(e.durationGuide, isNull);
    endWindow(e, c);
    expect(result(e)['outcome'], 'CORRECT_WITHHOLD');
    validate(e, capture(e));
  });
  test('G3 bar follows the pressed key and never leaks the correct target', () {
    final c = ManualClock(), e = held(c, 'G3_SWITCH');
    ready(e, c);
    expect(e.durationGuide, isNull);
    final wrong = (e.expected.single + 1) % 3;
    e.down(1, wrong);
    c.now += 200000;
    expect(e.durationGuide!.key, wrong);
    expect(e.durationGuide!.progress, .5);
    e.up(1);
    endWindow(e, c);
    expect(result(e)['outcome'], 'WRONG_KEY');
    validate(e, capture(e));
  });
  for (final level in [1, 4]) {
    for (final error in [0, 100000, 250000]) {
      test(
        'S2 L$level onset +$error gets 400 ms without shifting the next beat',
        () {
          final c = ManualClock(), e = held(c, 'S2_RHYTHM', level: level);
          ready(e, c);
          final original = e.scheduledBeatUs;
          c.now = original + error;
          e.down(1, e.expected.single);
          c.now += 400000;
          e.up(1);
          if (e.phase == 'cue') e.cuePresented();
          if (e.completed == 0) {
            c.now = original + 400000;
            e.tick();
            if (e.phase == 'cue') e.cuePresented();
          }
          expect(result(e)['outcome'], 'HIT');
          expect(result(e)['beat_error_us'], error);
          expect(result(e)['active_duration_us'], 800000);
          expect(
            e.scheduledBeatUs - original,
            60000000 ~/ [40, 45, 50, 55][level - 1],
          );
          validate(e, capture(e));
        },
      );
    }
  }
  test('S2 short press is TOO_SHORT then continues, no false hit time', () {
    final c = ManualClock(), e = held(c, 'S2_RHYTHM');
    ready(e, c);
    final at = e.scheduledBeatUs;
    c.now = at;
    press(e, c, e.expected.single, 100000);
    c.now = at + 400000;
    e.tick();
    expect(result(e)['outcome'], 'TOO_SHORT');
    expect(result(e)['beat_error_us'], isNull);
    expect(e.trialIndex, 1);
    validate(e, capture(e));
  });
  test(
    'S2 late hold is capped at the next window and does not block cadence',
    () {
      final c = ManualClock(), e = held(c, 'S2_RHYTHM', level: 4);
      ready(e, c);
      final at = e.scheduledBeatUs;
      c.now = at + 399999;
      e.down(1, e.expected.single);
      c.now = at + 400000;
      e.tick();
      expect(e.phase, 'holdTail');
      c.now = at + 60000000 ~/ 55 - 400000;
      e.tick();
      expect(result(e)['outcome'], 'TOO_SHORT');
      expect(e.phase, 'cue');
      e.cuePresented();
      expect(e.phase, 'response');
      e.up(1);
      validate(e, capture(e));
    },
  );
  test(
    'S2 lead-in supplies four BPM-spaced clicks before the first target',
    () {
      final c = ManualClock(), e = held(c, 'S2_RHYTHM');
      ready(e, c);
      final ticks = e.events
          .where((v) => v['kind'] == 'METRONOME_TICK')
          .toList();
      expect(ticks, hasLength(4));
      for (var i = 1; i < 4; i++) {
        expect(
          ticks[i]['payload']['scheduled_offset_us'] -
              ticks[i - 1]['payload']['scheduled_offset_us'],
          1500000,
        );
      }
      expect(
        e.scheduledBeatUs - ticks.last['payload']['scheduled_offset_us'],
        1500000,
      );
      validate(e, capture(e));
    },
  );
  test('S2 paused hold tail retains same attempt and original beat error', () {
    final c = ManualClock(), e = held(c, 'S2_RHYTHM');
    ready(e, c);
    final at = e.scheduledBeatUs;
    c.now = at + 100000;
    e.down(1, e.expected.single);
    c.now = at + 400000;
    e.tick();
    expect(e.phase, 'holdTail');
    final id = e.attempts.last['attempt_id'];
    e.pause('USER');
    c.now += 3000000;
    e.resume();
    c.now += 100000;
    e.up(1);
    expect(e.attempts.first['attempt_id'], id);
    expect(result(e)['outcome'], 'HIT');
    expect(result(e)['beat_error_us'], 100000);
    expect(result(e)['active_duration_us'], 800000);
    validate(e, capture(e));
  });
  test('short note released during pause is retried after resume', () {
    final c = ManualClock(), e = held(c, 'G1_MEMORY');
    ready(e, c);
    final notes = List<int>.from(e.expected);
    e.down(1, notes.first);
    c.now += 200000;
    e.pause('USER');
    c.now += 2000000;
    e.up(1);
    e.resume();
    expect(e.phase, 'response');
    expect(e.durationTooShort, true);
    for (final key in notes) {
      press(e, c, key, 400000);
    }
    c.now += 300000;
    e.tick();
    expect(result(e)['short_press_count'], 1);
    validate(e, capture(e));
  });
  test('L4 lead-in stays on its rational schedule even with late ticks', () {
    final c = ManualClock(), e = held(c, 'S2_RHYTHM', level: 4);
    ready(e, c);
    final ticks = e.events.where((v) => v['kind'] == 'METRONOME_TICK').toList();
    expect(
      e.scheduledBeatUs - ticks.last['payload']['scheduled_offset_us'],
      60000000 ~/ 55,
    );
  });
}
