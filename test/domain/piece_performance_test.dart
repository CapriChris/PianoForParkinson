import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:flutter/material.dart';

import 'scrolling_piece_test.dart' show score;

Json completedRecord() {
  final clock = ManualClock();
  final player = ScrollingPiecePlayer(score(), clock, tempo: 60)..start();
  clock.now = 4000000;
  player.down(1, 2);
  player.up(1);
  player.down(2, 2); // Same note counts once.
  player.up(2);
  player.down(3, 0);
  player.up(3);
  clock.now = 36000000;
  player.tick();
  return PiecePerformance.completed(player, DateTime.now());
}

void main() {
  test(
    'completed record snapshots matched notes without duplicate presses',
    () {
      final r = completedRecord();
      PiecePerformance.validate(r);
      expect(r['matched_notes'], [0]);
      expect(r['wrong_presses'], 1);
      expect(r['duration_us'], 32000000);
      expect(r['total_notes'], 30);
    },
  );
  test('only a complete performance can produce a record', () {
    final p = ScrollingPiecePlayer(score(), ManualClock(), tempo: 60)..start();
    expect(
      () => PiecePerformance.completed(p, DateTime.now()),
      throwsStateError,
    );
  });
  test('invalid counts, altered hash and changed envelope are rejected', () {
    final r = completedRecord();
    for (final change in <Json>[
      {
        'matched_notes': [0, 0],
      },
      {
        'matched_notes': [30],
      },
      {'wrong_presses': -1},
      {'duration_us': 1},
      {'tempo_bpm': 90},
    ]) {
      expect(
        () => PiecePerformance.validate({...r, ...change}),
        throwsFormatException,
      );
    }
    final row = {...r, 'record_json': canonical(r), 'record_hash': digest(r)};
    expect(PiecePerformance.fromRow(row), r);
    expect(
      () => PiecePerformance.fromRow({...row, 'record_hash': '0' * 64}),
      throwsFormatException,
    );
    expect(
      () => PiecePerformance.fromRow({...row, 'content_id': 'changed'}),
      throwsFormatException,
    );
  });
  test('treble C4 ledger, D4 space, E4 line, F4 space and G4 line', () {
    const g = ScrollingScoreGeometry(Size(400, 200));
    expect(g.pitchY(0), closeTo(g.staffBottom + g.staffGap, 1e-10));
    expect(g.pitchY(1), closeTo(g.staffBottom + g.staffGap / 2, 1e-10));
    expect(g.pitchY(2), closeTo(g.staffBottom, 1e-10));
    expect(g.pitchY(3), closeTo(g.staffBottom - g.staffGap / 2, 1e-10));
    expect(g.pitchY(4), closeTo(g.staffBottom - g.staffGap, 1e-10));
    for (final n in score().notes) {
      expect(g.noteRect(n, 0).center.dy, closeTo(g.pitchY(n.key), 1e-10));
    }
  });
}
