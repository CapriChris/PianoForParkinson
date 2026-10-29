import 'dart:convert';
import 'dart:io';

import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/features/piece_review_score.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/domain/piece_trace.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';

import 'scrolling_piece_test.dart' show score;

Json tracedRecord() {
  final clock = ManualClock();
  final p = ScrollingPiecePlayer(score(), clock, tempo: 60)
    ..start(leadBeats: 0);
  p.down(1, 2);
  clock.now = 400000;
  p.up(1);
  clock.now = 600000;
  p.down(2, 0);
  clock.now = 800000;
  p.up(2);
  clock.now = 1000000;
  p.down(3, 2);
  clock.now = 1500000;
  p.pause();
  clock.now = 3500000;
  p.resume();
  clock.now = 3700000;
  p.down(4, 2);
  clock.now = 4000000;
  p.tick();
  p.soundOff(4);
  clock.now = 4100000;
  p.up(4);
  clock.now = 34000000;
  p.tick();
  return PiecePerformance.completed(p, DateTime.utc(2025, 10, 27));
}

void main() {
  test('all six complete scores retain every note across rests, pickups and tied bar fragments', () {
    for (final slug in [
      'ode-to-joy',
      'frere-jacques',
      'twinkle',
      'saints',
      'happy-birthday',
      'you-are-my-sunshine',
    ]) {
      final piece = PianoPiece.fromJson(
        jsonDecode(
          File('assets/content/piece-$slug-001.json').readAsStringSync(),
        ) as Json,
      );
      final found = <int>{};
      var end = 0;
      for (
        var bar = 0;
        bar < piece.bars + (piece.pickupTicks > 0 ? 1 : 0);
        bar++
      ) {
        final g = ReviewStaffLayout(piece, bar, 340);
        expect(g.start, end);
        expect(g.end, greaterThan(g.start));
        end = g.end;
        for (final index in g.indices) {
          final box = g.rect(piece.notes[index]);
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.right, lessThanOrEqualTo(g.width));
          expect(box.top, greaterThanOrEqualTo(0));
          expect(box.bottom, lessThanOrEqualTo(g.height));
          expect(g.hit(box.center), index);
          found.add(index);
        }
      }
      expect(end, piece.ticks);
      expect(found.length, piece.notes.length);
    }
  });

  test('records actual wrong/repeated/overlapping timing, pause and automatic sound-off', () {
    final r = tracedRecord();
    PiecePerformance.validate(r);
    final s = r['performance_trace'] as Json;
    expect(s['duration_us'], 34000000);
    expect(s['notes'], hasLength(4));
    final n = s['notes'] as List;
    expect(n[0]['start_us'], 0);
    expect(n[0]['end_us'], 400000);
    expect(n[1]['key'], 0);
    expect(n[1]['matched_note'], isNull);
    expect(n[2]['end_us'], 1500000);
    expect(n[2]['touch_end_us'], 1500000);
    expect(n[3]['start_us'], 1700000);
    expect(n[3]['wall_start_us'], 3700000);
    expect(n[3]['end_us'], 2000000);
    expect(n[3]['touch_end_us'], 2100000);
    expect(s['pauses'], [
      {'score_us': 1500000, 'start_us': 1500000, 'end_us': 3500000},
    ]);
    expect(r['score_snapshot']['content_hash'], r['content_hash']);
  });
  test(
    'replay mapping keeps pauses and can also omit them without changing notes',
    () {
      final r = tracedRecord(), d = PieceReviewData(tracedRecord(), score());
      expect(d.canReplay, isTrue);
      expect(d.scoreAt(2500000, preservePauses: true), 1500000);
      expect(d.scoreAt(3700000, preservePauses: true), 1700000);
      expect(d.wallAt(1700000), 3700000);
      expect(d.segments(true), [
        {'target_us': 0, 'source_us': 0, 'duration_us': 1500000},
        {'target_us': 3500000, 'source_us': 1500000, 'duration_us': 30500000},
      ]);
      expect(d.replayNotes(true).last, {
        'key': 2,
        'start_us': 3700000,
        'duration_us': 300000,
      });
      expect(d.replayNotes(false).last['start_us'], 1700000);
      expect(d.demoNotes().length, score().noteCount);
      expect(r['matched_notes'], tracedRecord()['matched_notes']);
    },
  );
  test('completed snapshot is independent of later mutations and legacy records stay valid', () {
    final r = tracedRecord();
    final legacy = {...r}
      ..remove('performance_trace')
      ..remove('score_snapshot');
    PiecePerformance.validate(legacy);
    expect(PieceReviewData(legacy, score()).canReplay, isFalse);
    for (final patch in <Json>[
      {'duration_us': -1},
      {
        'notes': [
          {'key': 99, 'start_us': 0},
        ],
      },
      {
        'pauses': [
          {'score_us': 1, 'start_us': 9, 'end_us': 2},
        ],
      },
    ]) {
      final clone = jsonDecode(canonical(r)) as Json;
      (clone['performance_trace'] as Json).addAll(patch);
      expect(() => PiecePerformance.validate(clone), throwsFormatException);
    }
    final changed = jsonDecode(canonical(r)) as Json;
    changed['score_snapshot']['notes'][0]['duration_ticks'] = 99;
    expect(() => PiecePerformance.validate(changed), throwsFormatException);
  });
  test('overlapping keys and an empty performance are genuine replayable recordings', () {
    final clock = ManualClock();
    final p = ScrollingPiecePlayer(score(), clock, tempo: 60)
      ..start(leadBeats: 0);
    p.down(1, 2);
    p.down(2, 0);
    clock.now = 300000;
    p.up(1);
    clock.now = 500000;
    p.up(2);
    clock.now = p.totalUs;
    p.tick();
    final r = PiecePerformance.completed(p, DateTime.utc(2026));
    PiecePerformance.validate(r);
    expect(r['performance_trace']['notes'].map((n) => n['end_us']), [
      300000,
      500000,
    ]);
    final empty = ScrollingPiecePlayer(score(), clock, tempo: 60)
      ..start(leadBeats: 0);
    clock.now += empty.totalUs;
    empty.tick();
    final e = PiecePerformance.completed(empty, DateTime.utc(2026));
    PiecePerformance.validate(e);
    expect(e['performance_trace']['notes'], isEmpty);
    expect(PieceReviewData(e, score()).canReplay, isTrue);
  });
}
