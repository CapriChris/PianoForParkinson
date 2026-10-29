import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';

import 'responsive_controls_test.dart'
    show responsive, advanceTo, enterRhythmDemo;
import 'task_engine_test.dart' show ready;
import 'record_metrics_test.dart' show capture, validate;

void main() {
  for (var level = 1; level <= 4; level++) {
    test('S2 level $level four prep beats precede demo on the next beat', () {
      final c = ManualClock(), e = responsive(c, 'S2_RHYTHM', level: level);
      c.now = 300000;
      e.tick();
      final start = c.now;
      expect(e.preparingDemo, true);
      for (var beat = 0; beat < 4; beat++) {
        advanceTo(e, c, start + beat * 60000000 ~/ e.bpm);
        expect(e.leadInBeat, beat + 1);
        expect(e.phraseProgress, 0);
        expect(e.audio.where((a) => a['kind'] == 'demo'), isEmpty);
      }
      final end = start + 4 * 60000000 ~/ e.bpm;
      advanceTo(e, c, end - 1);
      expect(e.preparingDemo, true);
      advanceTo(e, c, end);
      expect(e.phase, 'demo');
      expect(e.rhythmPulse, 0);
      final prep = e.events
          .where(
            (v) =>
                v['kind'] == 'METRONOME_TICK' &&
                v['payload']['owner'] == 'DEMO_LEAD_IN',
          )
          .toList();
      expect(prep, hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect(
          prep[i]['payload']['scheduled_offset_us'],
          start + i * 60000000 ~/ e.bpm,
        );
      }
      final firstDemo = e.events.singleWhere(
        (v) => v['kind'] == 'METRONOME_TICK' && v['payload']['owner'] == 'DEMO',
      );
      expect(firstDemo['payload']['scheduled_offset_us'], end);
      validate(e, capture(e));
    });
    test(
      'S2 level $level demo and playing progress match beat cells exactly',
      () {
        final c = ManualClock(), e = responsive(c, 'S2_RHYTHM', level: level);
        enterRhythmDemo(e, c);
        final demoStart = c.now;
        final samples = <int, double>{};
        for (final halfBeat in [0, 1, 3, 6, 9, 12]) {
          final elapsed = halfBeat * 60000000 ~/ (2 * e.bpm);
          advanceTo(e, c, demoStart + elapsed);
          samples[elapsed] = e.phraseProgress;
          expect(e.phraseProgress, closeTo(halfBeat / 16, 1e-6));
        }
        ready(e, c);
        final first = e.base + e.scheduledBeatUs;
        expect(
          e.phraseProgress,
          0,
          reason: 'An early response window must not fill the bar',
        );
        for (final sample in samples.entries) {
          advanceTo(e, c, first + sample.key);
          expect(e.phraseProgress, sample.value);
          expect(e.soundingNoteIndex, (sample.value * 8).floor());
        }
        final lastBeat = first + 7 * 60000000 ~/ e.bpm;
        advanceTo(e, c, lastBeat);
        expect(e.phraseProgress, 7 / 8);
        expect(e.soundingNoteIndex, 7);
        advanceTo(e, c, lastBeat + e.beatAfterUs + 20000);
        expect(e.phase, 'phraseEnd');
        expect(e.phraseProgress, lessThan(1));
        advanceTo(e, c, e.base + e.phraseEndUs);
        expect(e.phase, 'feedback');
        expect(e.phraseProgress, 1);
        validate(e, capture(e));
      },
    );
  }
  test(
    'S2 pre-demo countdown pauses without replaying consumed prep beats',
    () {
      final c = ManualClock(), e = responsive(c, 'S2_RHYTHM');
      c.now = 300000;
      e.tick();
      c.now += 200000;
      e.pause('USER');
      c.now += 5000000;
      e.resume();
      expect(e.preparingDemo, true);
      expect(e.leadInProgress, closeTo(200000 / 1500000, 1e-9));
      advanceTo(e, c, 300000 + 5000000 + 6000000);
      expect(e.phase, 'demo');
      expect(e.rhythmPulse, 0);
      expect(
        e.events.where(
          (v) =>
              v['kind'] == 'METRONOME_TICK' &&
              v['payload']['owner'] == 'DEMO_LEAD_IN',
        ),
        hasLength(4),
      );
    },
  );
  test(
    'S2 replay includes demo prep again; normal continue freezes progress',
    () {
      final c = ManualClock(), e = responsive(c, 'S2_RHYTHM');
      ready(e, c);
      advanceTo(e, c, e.base + e.scheduledBeatUs + 200000);
      final progress = e.phraseProgress;
      e.pause('USER');
      c.now += 3000000;
      expect(e.phraseProgress, progress);
      e.resume();
      expect(e.phraseProgress, progress);
      e.pause('USER');
      e.resume(replay: true);
      advanceTo(e, c, c.now + 300000);
      expect(e.preparingDemo, true);
      expect(e.phraseProgress, 0);
      while (e.phase != 'demo') {
        c.now += 20000;
        e.tick();
      }
      expect(
        e.events.where(
          (v) =>
              v['kind'] == 'METRONOME_TICK' &&
              v['payload']['owner'] == 'DEMO_LEAD_IN',
        ),
        hasLength(8),
      );
      validate(e, capture(e));
    },
  );
}
