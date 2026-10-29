import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/intro_lessons.dart';

void main() {
  test('touch lesson varies keys, short presses stay within 1/4 to 1/2, repeats keep the same key', () {
    final keys = <int>{}, durations = <int>{};
    for (var seed = 0; seed < 100; seed++) {
      final short = LessonDemo.create('T1', 0, random: Random(seed));
      expect(short.notes, hasLength(1));
      expect(short.notes.single, inInclusiveRange(0, 2));
      expect(short.holdMs / 400, inInclusiveRange(.25, .5));
      keys.add(short.notes.single!);
      durations.add(short.holdMs);
      final full = LessonDemo.create('T1', 1, random: Random(seed));
      expect(full.notes, hasLength(1));
      expect(full.holdMs, 400);
      final repeat = LessonDemo.create('T1', 2, random: Random(seed));
      expect(repeat.notes, [repeat.notes.first, repeat.notes.first]);
      expect(repeat.holdMs, 400);
    }
    expect(keys, {0, 1, 2});
    expect(durations.length, greaterThan(20));
  });
  test('rhythm adds piano after metronome then introduces rests on a complete four-beat timeline', () {
    expect(LessonDemo.create('T3', 0).notes, [null, null, null, null]);
    expect(LessonDemo.create('T3', 1).notes, [0, 0, 0, 0]);
    expect(LessonDemo.create('T3', 2).notes, [0, null, 0, null]);
    for (var page = 0; page < 3; page++) {
      expect(LessonDemo.create('T3', page).durationMs, 6000);
    }
  });
}
