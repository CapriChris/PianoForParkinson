import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'responsive_controls_test.dart' show responsive, advanceTo;
import 'task_engine_test.dart' show ready;
import 'hold_policy_test.dart' show held;

void finishItem(TaskEngine e) {
  final time = e.clock as ManualClock;
  if (e.memory) {
    for (final key in List<int>.from(e.expected)) {
      e.down(1, key);
      time.now += e.noteDurationUs;
      e.up(1);
    }
    time.now += 300000;
    e.tick();
  } else if (e.windowed) {
    time.now += e.responseRemainingUs!;
    e.tick();
  } else if (e.rhythm) {
    advanceTo(e, time, e.base + e.scheduledBeatUs + e.beatAfterUs);
  } else {
    e.down(1, e.expected.single);
    time.now += e.noteDurationUs;
    e.up(1);
  }
}

void main() {
  for (final task in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'S1_GUIDED',
    'S2_RHYTHM',
    'M1_ALTERNATE',
    'M2_DUAL_ZONE',
  ]) {
    test('$task first and second block numbers follow displayed stages', () {
      final time = ManualClock(), e = responsive(ManualClock(), task);
      final clock = e.clock as ManualClock;
      expect(time.now, 0);
      for (var block = 0; block < 2; block++) {
        final offset = e.completed;
        for (var i = 0; i < e.trialCount; i++) {
          ready(e, clock);
          if (e.rhythm) advanceTo(e, clock, e.base + e.scheduledBeatUs);
          expect(e.currentItemNumber, offset + i + 1);
          finishItem(e);
          expect(e.completed, offset + i + 1);
          if (e.memory || e.windowed || e.rhythm) {
            expect(e.currentItemNumber, e.completed);
            if (!e.ended) {
              final phase = e.phase;
              e.pause('USER');
              clock.now += 1200000;
              expect(e.currentItemNumber, e.completed);
              e.resume();
              expect(e.phase, phase);
              expect(e.currentItemNumber, e.completed);
            }
          }
        }
        if (e.finishingPhrase) advanceTo(e, clock, e.base + e.phraseEndUs);
        expect(e.currentItemNumber, e.completed);
        if (block == 0) {
          expect(e.phase, 'feedback');
          e.nextBlock();
          expect(e.currentItemNumber, offset + e.trialCount + 1);
        }
      }
      expect(e.ended, true);
      expect(e.currentItemNumber, e.planned);
    });
  }

  for (final task in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'M2_DUAL_ZONE',
  ]) {
    test('$task reading its counter is side effect free through feedback', () {
      final clock = ManualClock(), e = responsive(clock, task);
      ready(e, clock);
      finishItem(e);
      final before = canonical({
        'events': e.events,
        'attempts': e.attempts,
        'trials': e.trials,
        'blocks': e.blocks,
        'decisions': e.decisions,
        'completed': e.completed,
        'phase': e.phase,
        'trialIndex': e.trialIndex,
      });
      for (var i = 0; i < 30; i++) {
        expect(e.currentItemNumber, 1);
      }
      expect(
        canonical({
          'events': e.events,
          'attempts': e.attempts,
          'trials': e.trials,
          'blocks': e.blocks,
          'decisions': e.decisions,
          'completed': e.completed,
          'phase': e.phase,
          'trialIndex': e.trialIndex,
        }),
        before,
      );
    });
  }

  for (final task in ['G1_MEMORY', 'G2_INHIBITION', 'G3_SWITCH']) {
    test('$task legacy hold policy uses the recorded gap number', () {
      final clock = ManualClock(), e = held(clock, task);
      ready(e, clock);
      finishItem(e);
      expect(e.currentItemNumber, 1);
      ready(e, clock);
      expect(e.currentItemNumber, 2);
    });
  }
}
