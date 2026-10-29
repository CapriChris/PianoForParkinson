import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'record_metrics_test.dart' show capture, validate;
import 'task_engine_test.dart' show create;

// Unlike ManualClock, a live clock can advance between consecutive reads.
class AdvancingClock implements Clock {
  int time = 0;
  @override
  int get now => time++;
}

void main() {
  for (final taskId in ['G1_MEMORY', 'S1_GUIDED']) {
    test('$taskId finalization uses one live-clock boundary', () {
      final clock = AdvancingClock();
      final e = TaskEngine(
        config: create(ManualClock()).config,
        clock: clock,
        taskId: taskId,
        mode: 'ASSIST',
        level: 1,
        song: [0, 1],
        seed: 47,
      );
      for (var i = 0; i < 2500 && e.phase != 'response'; i++) {
        clock.time += 20000;
        e.tick();
        if (e.phase == 'cue') e.cuePresented();
      }
      expect(e.phase, 'response');
      for (final key in List<int>.from(e.expected)) {
        e.down(1, key);
        clock.time += 10000;
        e.up(1);
      }
      if (e.memory) {
        clock.time += 300000;
        e.tick();
      }
      final a = e.attempts.first;
      expect(a['validity'], 'VALID');
      expect(
        a['active_duration_us'],
        a['response_end_us'] - a['cue_anchor_us'],
      );
      expect(a['ended_offset_us'], a['response_end_us']);
      validate(e, capture(e));
    });
  }
}
