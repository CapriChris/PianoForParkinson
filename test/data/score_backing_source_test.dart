import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/contracts.dart';

import 'piece_score_audit_test.dart' show slugs, load;

Json source(String slug) => jsonDecode(
  File('tools/score_sources/backing-score-$slug.json').readAsStringSync(),
) as Json;
void main() {
  test('supplied scores and separate staff transcriptions retain hashes', () {
    final identities = <String>{};
    for (final slug in slugs) {
      final s = source(slug), p = load(slug);
      expect(digest({...s}..remove('score_hash')), s['score_hash']);
      expect(
        sha256
            .convert(
              File('tools/score_sources/${s['source']['file']}')
                  .readAsBytesSync(),
            )
            .toString(),
        s['source_sha256'],
      );
      expect(s['source']['kind'], 'user_image');
      if (s['source']['midi_file'] != null) {
        expect(
          sha256
              .convert(
                File('tools/score_sources/${s['source']['midi_file']}')
                    .readAsBytesSync(),
              )
              .toString(),
          s['source']['midi_sha256'],
        );
        expect(
          (s['events'] as List).every(
            (e) => [0, 2, 4, 5, 7, 9, 11].contains(e['midi'] % 12),
          ),
          isTrue,
        );
      }
      expect(s['total_ticks'], p.ticks);
      expect(p.accompaniment!['score_hash'], s['score_hash']);
      expect(s['voicing_adjustments'], isNull);
      for (final e in s['events'] as List) {
        expect(e['source_staff'], '2');
        expect(e['start_tick'], greaterThanOrEqualTo(0));
        expect(
          e['start_tick'] + e['duration_ticks'],
          lessThanOrEqualTo(p.ticks),
        );
      }
      final melody = s['melody_events'] as List;
      for (var i = 0; i < melody.length; i++) {
        final n = p.notes[i];
        expect(n.startTick, melody[i]['start_tick']);
        expect(n.ticks, melody[i]['duration_ticks']);
        expect(n.isRest ? null : p.keyMidi(n.key), melody[i]['midi']);
      }
      identities.add(digest(s['events']));
    }
    expect(identities.length, 6);
  });
  test('written bass chords and sharp notes are retained without the old jazz arrangement', () {
    final ode = source('ode-to-joy')['events'] as List;
    expect(ode.take(2).map((n) => n['midi']), [48, 55]);
    expect(
      ode.where((n) => n['source_measure'] == '11').map((n) => n['midi']),
      [47, 55, 56],
    );
    expect(
      ode.where((n) => n['source_measure'] == '12').map((n) => n['midi']),
      [57, 54, 55],
    );
    final saints = source('saints')['events'] as List;
    expect(saints.take(3).map((n) => n['midi']), [48, 52, 55]);
    expect(saints.take(3).map((n) => n['start_tick']), [16, 16, 16]);
    final birthday = source('happy-birthday')['events'] as List;
    expect(birthday.any((n) => n['midi'] == 54), isTrue);
    expect(
      birthday.where((n) => n['source_measure'] == '17').map((n) => n['midi']),
      [60, 55, 52],
    );
  });
  test(
    'extended bank has complete natural tails and safe sustain overlaps',
    () {
      final bank = jsonDecode(
        File('assets/content/piano_bank.json').readAsStringSync(),
      ) as Json;
      expect(bank['samples'], hasLength(17));
      for (final s in bank['samples'] as List) {
        expect(
          sha256
              .convert(File(s['path'] as String).readAsBytesSync())
              .toString(),
          s['sha256'],
        );
        expect(s['sample_frames'], greaterThan(s['sample_rate'] * 5));
        expect(s['loop_end'], lessThan(s['sample_frames']));
        expect(
          s['loop_end'] - s['loop_start'],
          greaterThan(s['crossfade_frames'] * 2),
        );
      }
    },
  );
}
