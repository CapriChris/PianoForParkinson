import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'record_metrics_test.dart' show capture, validate;
import 'task_engine_test.dart' show ready;

TaskEngine responsive(ManualClock c, String task, {int level = 1}) =>
    TaskEngine(
      config: PracticeConfig(
        jsonDecode(File('assets/config/demo.json').readAsStringSync()) as Json,
      ),
      clock: c,
      taskId: task,
      mode: 'ASSIST',
      level: level,
      song: [0, 1, 2, 4, 2, 1, 0, 0],
      seed: 47,
    );
Json lastResult(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;
void toGo(TaskEngine e, ManualClock c) {
  ready(e, c);
  while (e.target['trial_type'] == 'NO_GO') {
    c.now += e.responseWindowUs;
    e.tick();
    ready(e, c);
  }
}

void advanceTo(TaskEngine e, ManualClock c, int time) {
  while (c.now < time) {
    c.now = min(time, c.now + 20000);
    e.tick();
    if (e.phase == 'cue') e.cuePresented();
  }
}

void enterRhythmDemo(TaskEngine e, ManualClock c) {
  while (!e.preparingDemo) {
    c.now += 20000;
    e.tick();
  }
  final first = e.events.lastWhere(
    (v) =>
        v['kind'] == 'METRONOME_TICK' &&
        v['payload']['owner'] == 'DEMO_LEAD_IN' &&
        v['payload']['beat_index'] == 0,
  );
  advanceTo(
    e,
    c,
    e.base +
        (first['payload']['scheduled_offset_us'] as int) +
        4 * 60000000 ~/ e.bpm,
  );
}

void main() {
  for (final level in [2, 3, 4]) {
    test(
      'S2 level $level integer beat boundary synchronizes demo and formal timeline',
      () {
        final c = ManualClock(), e = responsive(c, 'S2_RHYTHM', level: level);
        enterRhythmDemo(e, c);
        final start = c.now;
        final third = start + 3 * 60000000 ~/ e.bpm;
        advanceTo(e, c, third - 1);
        expect(e.soundingNoteIndex, 2);
        advanceTo(e, c, third);
        expect(e.rhythmPulse, 3);
        expect(e.soundingNoteIndex, 3);
        ready(e, c);
        final first = e.base + e.scheduledBeatUs;
        final second = first + 60000000 ~/ e.bpm;
        advanceTo(e, c, second - 1);
        expect(e.soundingNoteIndex, 0);
        advanceTo(e, c, second);
        expect(e.rhythmPulse, 1);
        expect(e.soundingNoteIndex, 1);
      },
    );
  }
  for (final task in ['G1_MEMORY', 'G2_INHIBITION', 'G3_SWITCH']) {
    test('$task response countdown freezes during pause', () {
      final c = ManualClock(), e = responsive(c, task);
      ready(e, c);
      final remaining = e.responseRemainingUs!;
      c.now += 200000;
      e.pause('USER');
      c.now += 5000000;
      e.resume();
      expect(e.responseRemainingUs, remaining - 200000);
      expect(e.responseFraction, lessThan(1));
    });
  }
  for (final task in ['G1_MEMORY', 'S1_GUIDED']) {
    test('$task short feedback persists until next key down', () {
      final c = ManualClock(), e = responsive(c, task);
      ready(e, c);
      final key = e.expected.first;
      e.down(1, key);
      c.now += 100000;
      e.up(1);
      c.now += 1400000;
      e.tick();
      expect(e.durationTooShort, true);
      expect(e.durationGuide!.progress, .25);
      e.down(2, key);
      expect(e.durationTooShort, false);
      c.now += 400000;
      e.up(2);
      validate(e, capture(e));
    });
  }
  test(
    'G1 timeout clears short feedback and seals even with a pending touch',
    () {
      final c = ManualClock(), e = responsive(c, 'G1_MEMORY');
      ready(e, c);
      final end = c.now + e.responseRemainingUs!;
      c.now = end - 100000;
      e.down(1, e.expected.first);
      c.now = end;
      e.tick();
      expect(e.completed, 1);
      expect(e.durationTooShort, false);
      expect(lastResult(e)['outcome'], 'TIMEOUT');
      e.up(1);
      validate(e, capture(e));
    },
  );
  for (final task in ['G2_INHIBITION', 'G3_SWITCH']) {
    test('$task full hold advances at fill before release and deadline', () {
      final c = ManualClock(), e = responsive(c, task);
      toGo(e, c);
      final anchor = e.attempts.last['cue_anchor_us'] as int;
      e.down(1, e.expected.single);
      c.now += 400000;
      e.tick();
      expect(e.completed, 1);
      expect(e.phase, 'intertrial');
      expect(e.highlighted, isNull);
      expect(e.durationGuide, isNull);
      expect(lastResult(e)['outcome'], 'HIT');
      expect(lastResult(e)['active_duration_us'], 400000);
      expect(e.attempts.last['response_end_us'], anchor + 400000);
      e.up(1);
      validate(e, capture(e));
    });
    test(
      '$task short hold locks keyboard until deadline and never leaks next trial',
      () {
        final c = ManualClock(), e = responsive(c, task);
        toGo(e, c);
        final end = c.now + e.responseRemainingUs!;
        final key = e.expected.single;
        e.down(1, key);
        c.now += 100000;
        e.up(1);
        expect(e.inputLocked, true);
        final sounds = e.audio.length;
        e.down(2, key);
        e.up(2);
        expect(e.audio.length, sounds);
        c.now = end - 1;
        e.tick();
        expect(e.durationTooShort, true);
        expect(e.completed, 0);
        c.now = end;
        e.tick();
        expect(lastResult(e)['outcome'], 'TOO_SHORT');
        expect(lastResult(e)['response_action_count'], 1);
        expect(e.durationTooShort, false);
        ready(e, c);
        expect(e.durationTooShort, false);
        expect(e.inputLocked, false);
        validate(e, capture(e));
      },
    );
    test(
      '$task full release while paused completes on resumed active time',
      () {
        final c = ManualClock(), e = responsive(c, task);
        toGo(e, c);
        e.down(1, e.expected.single);
        c.now += 400000;
        e.pause('USER');
        e.up(1);
        c.now += 2000000;
        e.resume();
        e.tick();
        expect(e.completed, 1);
        expect(lastResult(e)['outcome'], 'HIT');
        validate(e, capture(e));
      },
    );
  }
  test('G2 no-go press shows held duration without advancing wait', () {
    final c = ManualClock(), e = responsive(c, 'G2_INHIBITION');
    ready(e, c);
    while (e.target['trial_type'] != 'NO_GO') {
      c.now += e.responseWindowUs;
      e.tick();
      ready(e, c);
    }
    final end = c.now + e.responseRemainingUs!;
    final before = e.completed;
    e.down(1, 1);
    c.now += 200000;
    e.tick();
    expect(e.durationGuide!.key, 1);
    expect(e.durationGuide!.progress, .5);
    c.now += 300000;
    e.tick();
    expect(e.completed, before);
    expect(e.phase, 'response');
    e.up(1);
    c.now = end;
    e.tick();
    expect(lastResult(e)['outcome'], 'COMMISSION');
    validate(e, capture(e));
  });
  test(
    'G1 replay and help separately replay same target with and without hints',
    () {
      final c = ManualClock(), e = responsive(c, 'G1_MEMORY');
      ready(e, c);
      final target = canonical(e.target);
      final demos = e.events
          .where(
            (v) =>
                v['kind'] == 'AUDIO_REQUEST' && v['payload']['owner'] == 'DEMO',
          )
          .length;
      e.pause('USER');
      e.resume(replay: true);
      ready(e, c);
      expect(canonical(e.target), target);
      expect(e.showAnswer, false);
      expect(e.highlighted, isNull);
      expect(e.trial['help_count'], 0);
      expect(
        e.events
            .where(
              (v) =>
                  v['kind'] == 'AUDIO_REQUEST' &&
                  v['payload']['owner'] == 'DEMO',
            )
            .length,
        demos + e.expected.length,
      );
      e.pause('USER');
      e.resume(help: true);
      ready(e, c);
      expect(canonical(e.target), target);
      expect(e.showAnswer, true);
      expect(e.highlighted, e.expected.first);
      expect(e.trial['help_count'], 1);
      e.pause('USER');
      e.resume(replay: true);
      ready(e, c);
      expect(e.showAnswer, false);
      validate(e, capture(e));
    },
  );
  test('S1 highlight and guide appear together and both hide on pause', () {
    final c = ManualClock(), e = responsive(c, 'S1_GUIDED');
    ready(e, c);
    expect(e.highlighted, e.durationGuide!.key);
    e.pause('USER');
    expect(e.highlighted, isNull);
    expect(e.durationGuide, isNull);
    c.now += 1000000;
    e.resume();
    expect(e.highlighted, e.durationGuide!.key);
  });
  test(
    'S2 demo has metronome, continuous progress and exact beat highlights',
    () {
      final c = ManualClock(), e = responsive(c, 'S2_RHYTHM');
      enterRhythmDemo(e, c);
      final start = c.now;
      expect(e.soundingNoteIndex, 0);
      advanceTo(e, c, start + e.beatIntervalUs - 1);
      expect(e.soundingNoteIndex, 0);
      expect(e.phraseProgress, greaterThan(0));
      advanceTo(e, c, start + e.beatIntervalUs);
      expect(e.soundingNoteIndex, 1);
      final clicks = e.events
          .where(
            (v) =>
                v['kind'] == 'METRONOME_TICK' &&
                v['payload']['owner'] == 'DEMO',
          )
          .toList();
      expect(clicks, hasLength(2));
      expect(
        clicks[1]['payload']['scheduled_offset_us'] -
            clicks[0]['payload']['scheduled_offset_us'],
        e.beatIntervalUs,
      );
    },
  );
  test(
    'S2 timeline changes at beat, not at next response window; pause freezes',
    () {
      final c = ManualClock(), e = responsive(c, 'S2_RHYTHM');
      ready(e, c);
      final beat = e.base + e.scheduledBeatUs;
      advanceTo(e, c, beat - 1);
      expect(e.soundingNoteIndex, isNull);
      advanceTo(e, c, beat);
      expect(e.soundingNoteIndex, 0);
      expect(e.rhythmPulse, 0);
      expect(e.highlighted, e.song.first);
      advanceTo(e, c, beat + e.beatIntervalUs - 1);
      expect(e.soundingNoteIndex, 0);
      advanceTo(e, c, beat + e.beatIntervalUs);
      expect(e.soundingNoteIndex, 1);
      expect(e.rhythmPulse, 1);
      final progress = e.phraseProgress;
      e.pause('USER');
      c.now += 3000000;
      expect(e.phraseProgress, progress);
      e.resume();
      expect(e.rhythmPulse, 1);
      validate(e, capture(e));
    },
  );
}
