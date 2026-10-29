import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/scrolling_score.dart';

PianoPiece score() => PianoPiece.fromJson(
  jsonDecode(
    File('test/fixtures/legacy-pieces/piece-ode-to-joy-001.json')
        .readAsStringSync(),
  ) as Json,
);

void main() {
  for (final tempo in [40, 50, 60, 70, 80]) {
    test(
      'front and tail align with the play line at all score boundaries $tempo BPM',
      () {
        final clock = ManualClock();
        final p = ScrollingPiecePlayer(score(), clock, tempo: tempo)..start();
        final lead = p.atTick(8);
        const g = ScrollingScoreGeometry(Size(720, 160));
        for (var i = 0; i < p.piece.notes.length; i++) {
          final note = p.piece.notes[i];
          clock.now = lead + p.atTick(note.startTick);
          p.tick();
          expect(p.currentIndex, i);
          expect(
            g.noteRect(note, p.positionTick).left,
            closeTo(g.cursorX, .001),
          );
          clock.now = lead + p.atTick(note.endTick) - 1;
          p.tick();
          expect(p.currentIndex, i);
          clock.now++;
          p.tick();
          expect(
            g.noteRect(note, p.positionTick).right,
            closeTo(g.cursorX, .001),
          );
        }
        expect(p.mode, ScrollPieceMode.complete);
      },
    );
  }

  test(
    'note rectangles keep duration ratios and travel from right to left',
    () {
      const g = ScrollingScoreGeometry(Size(720, 160));
      final eighth = g.noteRect(const PieceNote(1, 1, 0), 0);
      final quarter = g.noteRect(const PieceNote(1, 2, 0), 0);
      final dotted = g.noteRect(const PieceNote(1, 3, 0), 0);
      final half = g.noteRect(const PieceNote(1, 4, 0), 0);
      expect(eighth.width, closeTo(quarter.width / 2, 1e-10));
      expect(dotted.width, closeTo(quarter.width * 1.5, 1e-10));
      expect(half.width, closeTo(quarter.width * 2, 1e-10));
      expect(
        g.noteRect(const PieceNote(1, 2, 4), 2).left,
        lessThan(g.noteRect(const PieceNote(1, 2, 4), 0).left),
      );
    },
  );

  test(
    'lead in approaches the line and missed notes never hold the timeline',
    () {
      final clock = ManualClock();
      final p = ScrollingPiecePlayer(score(), clock, tempo: 60)..start();
      expect(p.positionTick, -8);
      expect(p.down(1, 2), isFalse);
      clock.now = 4000000;
      p.tick();
      expect(p.currentIndex, 0);
      p.down(1, 2);
      clock.now += 100000;
      p.up(1);
      clock.now = 5500000;
      p.tick();
      expect(p.currentIndex, 1);
      clock.now = 16500000;
      p.tick();
      expect(p.currentIndex, 12);
      clock.now = 36000000;
      p.tick();
      expect(p.mode, ScrollPieceMode.complete);
      expect(p.down(2, 2), isFalse);
    },
  );

  test('repeated pitches require a new press and pause freezes the score', () {
    final clock = ManualClock();
    final p = ScrollingPiecePlayer(score(), clock, tempo: 60)
      ..start(leadBeats: 0);
    p.down(1, 2);
    expect(p.targetPressed, isTrue);
    clock.now = 1000000;
    p.tick();
    expect(p.currentIndex, 1);
    expect(p.targetPressed, isFalse);
    p.up(1);
    p.down(2, 2);
    expect(p.targetPressed, isTrue);
    clock.now = 1250000;
    p.pause();
    final frozen = p.positionTick;
    expect(p.pointers, isEmpty);
    clock.now += 10000000;
    p.tick();
    expect(p.positionTick, frozen);
    p.resume();
    clock.now += 750000;
    p.tick();
    expect(p.currentIndex, 2);
    expect(p.targetPressed, isFalse);
  });
}
