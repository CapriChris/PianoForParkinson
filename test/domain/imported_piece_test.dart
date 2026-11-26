import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/domain/imported_piece.dart';
import 'package:piano_practice/domain/piano_piece.dart';

void main() {
  test('local melody draft preserves original audio and survives a score snapshot reload', () {
    final hash = 'a' * 64;
    final draft = ImportedPieceDraft({
      'title': 'Imported melody',
      'path': 'imports/$hash.mp3',
      'sha256': hash,
      'duration_ms': 3200,
      'notes': [
        {'midi': 60, 'start_ms': 0, 'end_ms': 450},
        {'midi': 64, 'start_ms': 1000, 'end_ms': 1400},
        {'midi': 67, 'start_ms': 2000, 'end_ms': 2600},
      ],
    });
    final piece = draft.build();
    final reloaded = PianoPiece.fromJson(piece.data);
    expect(reloaded.noteCount, 3);
    expect(reloaded.notes.any((note) => note.isRest), isTrue);
    expect(reloaded.accompanimentFor(30)?['path'], 'imports/$hash.mp3');
    expect(reloaded.accompanimentFor(30)?['base_tempo_bpm'], 60);
    expect(draft.preview().accompaniment, isNull);
    expect(draft.preview().noteCount, 3);
    draft.notes[1]['midi'] = 65;
    expect(
      draft.build().data['content_hash'],
      isNot(piece.data['content_hash']),
    );
  });

  test('untrusted imported audio paths cannot enter a score snapshot', () {
    final draft = ImportedPieceDraft({
      'title': 'Invalid path',
      'path': '../secret.mp3',
      'sha256': 'a' * 64,
      'duration_ms': 1000,
      'notes': [
        {'midi': 60, 'start_ms': 0, 'end_ms': 900},
      ],
    });
    expect(draft.build, throwsFormatException);
  });
}
