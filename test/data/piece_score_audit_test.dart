import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';

const slugs = [
  'ode-to-joy',
  'frere-jacques',
  'twinkle',
  'saints',
  'happy-birthday',
  'you-are-my-sunshine',
];
PianoPiece load(String slug) => PianoPiece.fromJson(
  jsonDecode(File('assets/content/piece-$slug-001.json').readAsStringSync())
      as Json,
);
List<int?> pitches(PianoPiece p) => [
  for (final n in p.notes) n.isRest ? null : p.keyMidi(n.key),
];
void main() {
  test('complete supplied scores retain their supplied registers and exact lengths', () {
    const counts = [62, 32, 42, 64, 68, 79];
    const beats = [64, 32, 48, 128, 69, 68];
    for (var i = 0; i < slugs.length; i++) {
      final p = load(slugs[i]);
      expect(p.ticksPerBeat, 4);
      expect(p.notes.length, counts[i]);
      expect(p.ticks, beats[i] * 4);
      expect(p.data['score_source']['kind'], 'user_image');
      expect(
        p.notes.where((n) => !n.isRest).map((n) => p.keyMidi(n.key)).toSet(),
        (p.data['key_midis'] as List).toSet(),
      );
    }
    expect(pitches(load('ode-to-joy')).take(8), [
      64,
      64,
      65,
      67,
      67,
      65,
      64,
      62,
    ]);
    expect(pitches(load('happy-birthday')).take(8), [
      null,
      null,
      67,
      67,
      69,
      67,
      72,
      71,
    ]);
    expect(pitches(load('you-are-my-sunshine')).take(5), [
      null,
      null,
      67,
      72,
      74,
    ]);
  });
  test('Frere preserves written dotted eighth/sixteenth and separate repeated attacks', () {
    final p = load('frere-jacques');
    expect(p.notes.skip(14).take(6).map((n) => n.ticks), [3, 1, 2, 2, 4, 4]);
    expect(p.notes.skip(26).map((n) => p.keyMidi(n.key)), [
      60,
      67,
      60,
      60,
      67,
      60,
    ]);
  });
  test('Saints merges ties across barlines and unfolds final repeat', () {
    final p = load('saints');
    expect(p.pickupTicks, 12);
    expect(p.notes.take(4).map((n) => n.ticks), [4, 4, 4, 20]);
    expect(pitches(p).take(32), pitches(p).skip(32));
    expect(
      p.notes.take(32).map((n) => n.ticks),
      p.notes.skip(32).map((n) => n.ticks),
    );
    expect(p.notes.last.ticks, 20);
  });
  test('Sunshine follows the supplied white-key score, including corrected passing notes', () {
    final p = load('you-are-my-sunshine');
    expect(p.data['version'], '2.1.0');
    expect(p.data['key_midis'], [67, 72, 74, 76, 77, 79, 81]);
    expect(p.keyCount, 7);
    expect(
      pitches(p)
          .whereType<int>()
          .every((n) => [0, 2, 4, 5, 7, 9, 11].contains(n % 12)),
      isTrue,
    );
    // Bar 2 has D5, rather than simply transposing the former A-flat to D-sharp.
    expect(pitches(p).skip(5).take(5), [76, 76, 76, 74, 76]);
    expect(p.notes.skip(5).take(5).map((n) => n.ticks), [4, 6, 2, 2, 2]);
    expect(p.keyLabel(0), '5');
    expect(p.keyLabel(1), '1\u0307');
    expect(p.keyLabel(6), '6\u0307');
    expect(pitches(p).last, 72);
    expect(p.notes.last.ticks, 16);
  });
  test('octave dots and degree shapes remain compatible with older scores', () {
    final p = PianoPiece.fromJson(
      jsonDecode(
        File('test/fixtures/legacy-pieces/piece-happy-birthday-001.json')
            .readAsStringSync(),
      ) as Json,
    );
    expect(p.keyLabel(0), '5\u0323');
    expect(p.keyShape(0), 4);
    expect(p.keyLabel(7), '5');
    expect(p.keyShape(7), 4);
  });
  test('all thirty backing assets match score durations and hashes', () {
    for (final slug in slugs) {
      final p = load(slug);
      for (final tempo in [40, 50, 60, 70, 80]) {
        final a = p.accompanimentFor(tempo)!;
        final bytes = File(a['path'] as String).readAsBytesSync();
        expect(
          sha256.convert(bytes).toString(),
          a['sha256'],
          reason: '$slug $tempo',
        );
        expect(ascii.decode(bytes.take(4).toList()), 'OggS');
        expect(
          a['duration_ms'],
          (p.ticks * 60000 / tempo / p.ticksPerBeat).round(),
        );
      }
    }
  });
}
