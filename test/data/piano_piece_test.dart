import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';

Json scoreJson() => jsonDecode(
  File('test/fixtures/legacy-pieces/piece-ode-to-joy-001.json')
      .readAsStringSync(),
) as Json;
PianoPiece piece() => PianoPiece.fromJson(scoreJson());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('independent catalog contains complete supplied Ode and excludes it from short tasks', () async {
    final content = ContentRepository();
    await content.load();
    expect(content.songs, hasLength(3));
    for (final song in content.songs) {
      expect(song['category'], 'ORIGINAL_EXERCISE');
      expect(song['notes'], hasLength(8));
    }
    expect(
      content.song['content_hash'],
      '56d16e11802da865d370745eeda2d3b94b9f3ddfbde7362aeedc6376e75163ca',
    );
    expect(content.pieces, hasLength(6));
    final score = content.pieces.first;
    expect(score.bars, 16);
    expect(score.ticks, 256);
    expect(score.notes, hasLength(62));
    expect(score.notes.take(8).map((n) => n.key), [2, 2, 3, 4, 4, 3, 2, 1]);
    expect(score.notes.skip(12).take(3).map((n) => n.ticks), [6, 2, 8]);
    for (var bar = 0; bar < 16; bar++) {
      expect(
        score.notes
            .where((n) => n.startTick ~/ 16 == bar)
            .fold(0, (sum, n) => sum + n.ticks),
        16,
      );
    }
  });

  test('modified hash, invalid duration, incomplete bar and invalid key are rejected', () {
    final corrupted = scoreJson();
    corrupted['notes'][0]['duration_ticks'] = 4;
    expect(() => PianoPiece.fromJson(corrupted), throwsFormatException);
    for (final field in ['duration_ticks', 'note_index']) {
      final invalid = scoreJson();
      invalid['notes'][0][field] = 9;
      invalid.remove('content_hash');
      invalid['content_hash'] = digest(invalid);
      expect(() => PianoPiece.fromJson(invalid), throwsFormatException);
    }
    final incomplete = scoreJson();
    (incomplete['notes'] as List).removeLast();
    incomplete.remove('content_hash');
    incomplete['content_hash'] = digest(incomplete);
    expect(() => PianoPiece.fromJson(incomplete), throwsFormatException);
  });

  for (final tempo in [40, 50, 60, 70, 80]) {
    test(
      'demo boundaries follow every score duration without drift at $tempo BPM',
      () {
        final clock = ManualClock();
        final p = PiecePlayer(piece(), clock)
          ..setTempo(tempo)
          ..start(demo: true);
        for (var i = 0; i < p.piece.notes.length; i++) {
          final note = p.piece.notes[i];
          clock.now = p.atTick(note.startTick);
          p.tick();
          expect(p.index, i);
          expect(p.progress, 0);
          clock.now = p.atTick(note.endTick) - 1;
          p.tick();
          expect(p.index, i);
          expect(p.mode, PieceMode.demo);
        }
        clock.now = p.atTick(64);
        p.tick();
        expect(p.mode, PieceMode.ready);
      },
    );

    test(
      'all note lengths reject short holds and complete after exact duration at $tempo BPM',
      () {
        final clock = ManualClock();
        final p = PiecePlayer(piece(), clock)
          ..setTempo(tempo)
          ..start(demo: false);
        for (var i = 0; i < 30; i++) {
          expect(p.down(1, p.note.key), isTrue);
          clock.now += p.durationUs - 1;
          p.up(1);
          expect(p.tooShort, isTrue);
          expect(p.index, i);
          expect(p.down(2, p.note.key), isTrue);
          clock.now += p.durationUs;
          p.up(2);
          expect(p.index, i + 1);
        }
        expect(p.mode, PieceMode.complete);
      },
    );
  }

  test('60 BPM contains 500 ms, 1 s, 1.5 s and 2 s notes', () {
    final p = PiecePlayer(piece(), ManualClock());
    final durations = <int>{};
    for (var i = 0; i < 30; i++) {
      p.index = i;
      durations.add(p.durationUs);
    }
    expect(durations, {500000, 1000000, 1500000, 2000000});
  });

  test('demo pause freezes current dotted note and resumes remaining time', () {
    final clock = ManualClock();
    final p = PiecePlayer(piece(), clock)..start(demo: true);
    clock.now = 12500000;
    p.tick();
    expect(p.index, 12);
    p.pause();
    final frozenProgress = p.progress;
    clock.now += 10000000;
    p.tick();
    expect(p.index, 12);
    expect(p.progress, frozenProgress);
    p.resume();
    clock.now += 999999;
    p.tick();
    expect(p.index, 12);
    clock.now++;
    p.tick();
    expect(p.index, 13);
  });

  test('stopping a paused demo resets the score and permits a new tempo', () {
    final clock = ManualClock();
    final p = PiecePlayer(piece(), clock)..start(demo: true);
    clock.now = 13000000;
    p.tick();
    p.pause();
    p.stop();
    expect(p.mode, PieceMode.ready);
    expect(p.index, 0);
    p.setTempo(40);
    p.start(demo: false);
    expect(p.durationUs, 1500000);
  });

  test('wrong keys, canceled touches and paused holds do not advance', () {
    final clock = ManualClock();
    final p = PiecePlayer(piece(), clock)..start(demo: false);
    expect(p.down(1, 0), isFalse);
    expect(p.wrongKey, isTrue);
    expect(p.index, 0);
    p.down(2, 2);
    clock.now += 1000000;
    p.up(2, cancel: true);
    expect(p.index, 0);
    p.down(3, 2);
    clock.now += 500000;
    p.pause();
    clock.now += 10000000;
    p.resume();
    p.up(3);
    expect(p.index, 0);
    expect(p.progress, 0);
    p.down(4, 2);
    clock.now += 1000000;
    p.up(4);
    expect(p.index, 1);
  });
}
