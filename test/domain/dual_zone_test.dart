import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import 'record_metrics_test.dart' show capture, validate;
import 'task_engine_test.dart' show ready;

TaskEngine dual(ManualClock clock, {int level = 1}) => TaskEngine(
  config: PracticeConfig(
    jsonDecode(File('assets/config/demo.json').readAsStringSync()) as Json,
  ),
  clock: clock,
  taskId: 'M2_DUAL_ZONE',
  mode: 'ASSIST',
  level: level,
  song: [],
  seed: 47,
);
Json result(TaskEngine e) =>
    e.attempts.lastWhere((a) => a['validity'] == 'VALID')['result'] as Json;
void finishWindow(TaskEngine e, ManualClock clock) {
  clock.now += e.responseRemainingUs!;
  e.tick();
}

void main() {
  for (var level = 1; level <= 4; level++) {
    for (final reverse in [false, true]) {
      for (final late in [0, 1]) {
        test(
          'dual L$level reversed=$reverse tolerance+$late full window, overlap allowed',
          () {
            final c = ManualClock(), e = dual(ManualClock());
            final clock = e.clock as ManualClock;
            e.level = level;
            // A fresh block captures this level and its tolerance.
            final task = dual(clock, level: level);
            ready(task, clock);
            final pair = task.expected;
            task.down(1, pair[reverse ? 1 : 0]);
            clock.now += task.dualToleranceUs + late;
            task.down(2, pair[reverse ? 0 : 1]);
            expect(task.completed, 0);
            finishWindow(task, clock);
            expect(result(task)['outcome'], late == 0 ? 'HIT' : 'OUT_OF_SYNC');
            expect(result(task)['gap_us'], task.dualToleranceUs + late);
            expect(result(task)['overlap_count'], 0);
            expect(result(task)['active_duration_us'], 3000000);
            task.up(1);
            task.up(2);
            validate(task, capture(task));
            expect(c.now, 0);
          },
        );
      }
    }
  }
  test('dual error priority, duplicate, missing and no early completion', () {
    for (final scenario in [
      'none',
      'one',
      'wrong',
      'duplicate',
      'outside',
      'extra',
    ]) {
      final c = ManualClock(), e = dual(ManualClock());
      final clock = e.clock as ManualClock;
      ready(e, clock);
      if (scenario != 'none') e.down(1, scenario == 'wrong' ? 2 : 0);
      if (['duplicate', 'extra', 'outside'].contains(scenario)) {
        e.down(
          2,
          scenario == 'duplicate'
              ? 0
              : scenario == 'outside'
              ? null
              : 3,
        );
      }
      if (scenario == 'extra') e.down(3, 3);
      finishWindow(e, clock);
      expect(
        result(e)['outcome'],
        ['none', 'one'].contains(scenario) ? 'OMISSION' : 'WRONG_OR_EXTRA',
      );
      expect(result(e)['gap_us'], isNull);
      validate(e, capture(e));
      expect(c.now, 0);
    }
  });
  test('two blocks, gaps include out-of-sync, user pause excludes pause time and contract rejects tampering', () {
    final clock = ManualClock(), e = dual(ManualClock());
    final c = e.clock as ManualClock;
    for (var block = 0; block < 2; block++) {
      for (var i = 0; i < 12; i++) {
        ready(e, c);
        expect(e.expected, [i % 3, i % 3 + 3]);
        e.down(1, e.expected[0]);
        if (i == 0) {
          e.pause('USER');
          c.now += 5000000;
          e.resume();
        }
        c.now += 200000;
        e.down(2, e.expected[1]);
        finishWindow(e, c);
        e.up(1);
        e.up(2);
      }
      if (block == 0) e.nextBlock();
    }
    expect(e.ended, true);
    expect(e.completed, 24);
    expect(e.summary()['rates']['primary']['numerator'], 24);
    expect(e.summary()['timing_groups']['dual_gap']['samples'], 24);
    validate(e, capture(e));
    final bad = capture(e);
    bad['attempts'][0]['result']['gap_us'] = 1;
    expect(() => validate(e, bad), throwsFormatException);
    expect(clock.now, 0);
  });
}
