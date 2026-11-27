import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/domain/piece_timing.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';

PianoPiece shortScore() {
  final data = <String, dynamic>{
    'schema_version': 1,
    'content_id': 'timing-fixture',
    'localized_title': {'zh-Hans': '测试', 'en': 'Timing fixture'},
    'localized_description': {'zh-Hans': '测试', 'en': 'Test'},
    'ticks_per_beat': 4,
    'beats_per_bar': 4,
    'tempo_bpm': 60,
    'key_steps': [0, 1],
    'notes': [
      {'note_index': 0, 'duration_ticks': 4},
      {'note_index': 0, 'duration_ticks': 4},
      {'note_index': -1, 'duration_ticks': 8},
    ],
  };
  return PianoPiece.fromJson({...data, 'content_hash': digest(data)});
}

void main() {
  test('tempo drag snaps near tens and respects original tempo endpoints', () {
    expect(PieceTiming.snapTempo(48.2, 90), 50);
    expect(PieceTiming.snapTempo(51.8, 90), 50);
    expect(PieceTiming.snapTempo(53, 90), 53);
    expect(PieceTiming.snapTempo(29, 90), 30);
    expect(PieceTiming.snapTempo(78.9, 79), 79);
    expect(PieceTiming.snapTempo(99, 95), 95);
  });

  test('three-second count-in is independent of musical tempo', () {
    for (final tempo in [30, 45, 60]) {
      final clock = ManualClock();
      final p = ScrollingPiecePlayer(
        shortScore(),
        clock,
        tempo: tempo,
        training: true,
      )..start(leadBeats: 0, leadUs: 3000000);
      clock.now = 2999999;
      p.tick();
      expect(p.leadingIn, isTrue);
      clock.now = 3000000;
      p.tick();
      expect(p.elapsedUs, 0);
    }
  });
  for (final offset in [-150000, 150000, -150001, 150001]) {
    test('onset boundary $offset microseconds', () {
      final clock = ManualClock();
      final player = ScrollingPiecePlayer(
        shortScore(),
        clock,
        tempo: 60,
        training: true,
      )..start(leadBeats: 1);
      clock.now = 1000000 + offset;
      final accepted = player.down(1, 0);
      if (offset < -150000) {
        expect(accepted, isFalse);
        expect(player.trace.notes, isEmpty);
        return;
      }
      expect(accepted, isTrue);
      clock.now = 1000000 + player.noteEndUs(0);
      player.up(1);
      expect(player.matchedNotes.contains(0), offset.abs() <= 150000);
      expect(player.trace.notes.single['onset_offset_us'], offset);
    });
  }

  for (final offset in [-120000, 120000, -120001, 120001]) {
    test('release boundary $offset microseconds', () {
      final clock = ManualClock();
      final player = ScrollingPiecePlayer(
        shortScore(),
        clock,
        tempo: 60,
        training: true,
      )..start(leadBeats: 0);
      player.down(1, 0);
      clock.now = player.noteEndUs(0) + offset;
      player.up(1);
      expect(player.matchedNotes.contains(0), offset.abs() <= 120000);
      expect(player.trace.notes.single['release_offset_us'], offset);
      expect(player.trace.notes.single['hold_duration_us'], clock.now);
    });
  }

  test(
    'wrong keys and breaking a hold cannot be repaired by pressing again',
    () {
      final clock = ManualClock();
      final p = ScrollingPiecePlayer(
        shortScore(),
        clock,
        tempo: 60,
        training: true,
      )..start(leadBeats: 0);
      p.down(1, 1);
      clock.now = 10000;
      p.up(1);
      p.down(2, 0);
      clock.now = 100000;
      p.up(2);
      p.down(3, 0);
      clock.now = p.noteEndUs(0);
      p.up(3);
      expect(p.matchedNotes, isEmpty);
      expect(p.trace.notes.map((n) => n['success']), everyElement(false));
      expect(p.trace.notes[1]['judgement'], 'early_release');
    },
  );

  test('beginner freezes musical time, records the wait and resumes on the correct key', () {
    final clock = ManualClock();
    final p = ScrollingPiecePlayer(
      shortScore(),
      clock,
      tempo: 60,
      training: true,
      practiceMode: PiecePracticeMode.beginner,
    )..start(leadBeats: 0);
    p.tick();
    expect(p.waitingForKey, isTrue);
    clock.now = 2000000;
    p.tick();
    expect(p.elapsedUs, 0);
    p.followAudioPosition(1800000);
    expect(p.elapsedUs, 0);
    p.down(1, 1);
    p.up(1);
    expect(p.waitingForKey, isTrue);
    p.down(2, 0);
    expect(p.waitingForKey, isFalse);
    expect(p.trace.notes.last['waiting_us'], 2000000);
    expect(p.trace.notes.last['onset_offset_us'], 0);
    clock.now += p.noteEndUs(0);
    p.up(2);
    expect(p.matchedNotes, {0});
    clock.now = 3000000;
    p.tick();
    expect(p.elapsedUs, 1000000);
    expect(p.waitingForKey, isTrue);
  });

  test('pause ends continuity and a repeated pitch needs a fresh press', () {
    final clock = ManualClock();
    final p = ScrollingPiecePlayer(
      shortScore(),
      clock,
      tempo: 60,
      training: true,
    )..start(leadBeats: 0);
    p.down(1, 0);
    clock.now = 500000;
    p.pause();
    expect(p.trace.notes.single['judgement'], 'interrupted');
    clock.now += 4000000;
    p.resume();
    expect(p.elapsedUs, 500000);
    clock.now += 500000;
    p.down(2, 0);
    clock.now += 875000;
    p.up(2);
    expect(p.matchedNotes, {1});
  });

  test(
    'late physical release remains in the saved trace after the score ends',
    () {
      final clock = ManualClock();
      final p = ScrollingPiecePlayer(
        shortScore(),
        clock,
        tempo: 60,
        training: true,
      )..start(leadBeats: 0);
      clock.now = 1000000;
      p.down(1, 0);
      clock.now = 5000000;
      p.tick();
      expect(p.mode, ScrollPieceMode.running);
      p.up(1);
      p.tick();
      final record = PiecePerformance.completed(p, DateTime.now());
      PiecePerformance.validate(record);
      final press = record['performance_trace']['notes'].single as Json;
      expect(press['success'], isFalse);
      expect(press['hold_duration_us'], 4000000);
      expect(press['touch_end_us'], 5000000);
    },
  );
}
