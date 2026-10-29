import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/record_snapshot.dart';
import 'package:piano_practice/domain/contracts.dart';

import 'alternate_test.dart' show answer;
import 'responsive_controls_test.dart' show responsive, advanceTo;
import 'task_engine_test.dart' show ready;
import 'record_metrics_test.dart' show capture, validate;

void main() {
  for (final task in ['S2_RHYTHM', 'M1_ALTERNATE']) {
    for (var level = 1; level <= 4; level++) {
      for (final error in [-400000, 0, 399999]) {
        test(
          '$task level $level error $error waits for the complete final beat in both blocks',
          () {
            final clock = ManualClock(),
                e = responsive(clock, task, level: level);
            for (var block = 0; block < 2; block++) {
              for (var note = 0; note < e.trialCount - 1; note++) {
                answer(e, clock);
              }
              if (e.phase == 'cue') e.cuePresented();
              final target = e.base + e.scheduledBeatUs;
              final end = e.base + e.phraseEndUs;
              advanceTo(e, clock, target + error);
              e.down(1, e.expected.single);
              advanceTo(e, clock, clock.now + 400000);
              e.up(1);
              advanceTo(e, clock, target + 800000);
              expect(e.phase, 'phraseEnd');
              expect(e.ended, false);
              expect(e.inputLocked, true);
              expect(e.durationGuide, isNull);
              expect(e.highlighted, isNull);
              expect(e.currentItemNumber, (block + 1) * e.trialCount);
              expect(e.phraseProgress, lessThan(1));
              final results = capture(e)['attempts'];
              validate(e, capture(e));
              advanceTo(e, clock, end - 1);
              expect(e.finishingPhrase, true);
              advanceTo(e, clock, end);
              expect(e.phraseProgress, 1);
              expect(e.phase, block == 0 ? 'feedback' : 'finished');
              expect(canonical(capture(e)['attempts']), canonical(results));
              validate(e, capture(e));
              if (block == 0) e.nextBlock();
            }
          },
        );
      }
    }
    for (final reason in ['USER', 'INTERRUPTED_BACKGROUND']) {
      test(
        '$task final phrase pause $reason freezes and never replays or rescores',
        () {
          final clock = ManualClock(), e = responsive(clock, task);
          for (var note = 0; note < e.trialCount - 1; note++) {
            answer(e, clock);
          }
          ready(e, clock);
          final target = e.base + e.scheduledBeatUs;
          advanceTo(e, clock, target + e.beatAfterUs);
          expect(e.phase, 'phraseEnd');
          final progress = e.phraseProgress, count = e.attempts.length;
          final end = e.base + e.phraseEndUs;
          e.pause(reason);
          clock.now += 5000000;
          if (reason == 'USER') expect(e.phraseProgress, progress);
          e.resume();
          expect(e.phase, 'phraseEnd');
          expect(e.phraseProgress, closeTo(progress, 1e-9));
          advanceTo(e, clock, end + 5000000);
          expect(e.phase, 'feedback');
          expect(e.attempts, hasLength(count));
          validate(e, capture(e));
        },
      );
    }
    test(
      '$task record worker freezes input before asynchronous validation and preserves row encoding',
      () async {
        final clock = ManualClock(), e = responsive(clock, task);
        ready(e, clock);
        final data = capture(e)..['decisions'] = e.decisions;
        final before = canonical(e.summary());
        final request = <String, dynamic>{
          'data': data,
          'id': e.id,
          'epoch': e.epoch,
          'task_id': e.taskId,
          'slots': e.config.blocks,
          'maximum': e.config.maximum(task),
          'metric_version': e.config.json['metric_version'],
          'prepare_rows': true,
        };
        final future = compute(prepareRecordSnapshot, request);
        // Mutating the caller immediately must not corrupt a queued snapshot.
        (data['blocks'] as List).clear();
        final snapshot = await future;
        expect(canonical(snapshot['summary']), before);
        expect(snapshot['blocks'], hasLength(1));
        final prepared =
            snapshot['_prepared_rows']['blocks'][e.block['block_id']];
        expect(prepared['fingerprint'], canonical(prepared['values']));
        expect(
          prepared['values']['targets_json'],
          canonical(e.block['targets']),
        );
        expect(snapshot['_prepared_rows']['events'].length, e.events.length);
      },
    );
  }
  for (final task in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'S1_GUIDED',
    'S2_RHYTHM',
    'M1_ALTERNATE',
  ]) {
    test(
      '$task item number starts at one and represents the currently presented item',
      () {
        final clock = ManualClock(), e = responsive(clock, task);
        expect(e.currentItemNumber, 1);
        ready(e, clock);
        expect(e.currentItemNumber, 1);
        if (e.memory || e.windowed) {
          advanceTo(e, clock, clock.now + e.responseRemainingUs!);
        } else if (e.rhythm) {
          advanceTo(e, clock, e.base + e.scheduledBeatUs + e.beatAfterUs);
        } else {
          e.down(1, e.expected.single);
          clock.now += 400000;
          e.up(1);
        }
        ready(e, clock);
        if (e.rhythm) {
          // The next matching window opens before its beat. Numbering follows
          // the visible beat and must keep the previous item until then.
          expect(e.currentItemNumber, 1);
          advanceTo(e, clock, e.base + e.scheduledBeatUs);
        }
        expect(e.currentItemNumber, 2);
      },
    );
  }
}
