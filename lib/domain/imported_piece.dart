import 'contracts.dart';
import 'piano_piece.dart';

class ImportedPieceDraft {
  ImportedPieceDraft(Json analysis)
    : notes = [
        for (final note in analysis['notes'] as List)
          Map<String, dynamic>.from(note as Map),
      ],
      path = analysis['path'] as String,
      audioHash = analysis['sha256'] as String,
      durationMs = analysis['duration_ms'] as int,
      title = analysis['title'] as String {
    final intervals = <int>[];
    for (var i = 1; i < notes.length; i++) {
      final gap =
          (notes[i]['start_ms'] as int) - (notes[i - 1]['start_ms'] as int);
      if (gap >= 80 && gap <= 2000) intervals.add(gap);
    }
    intervals.sort();
    var estimate = intervals.isEmpty
        ? 60.0
        : 60000 / intervals[intervals.length ~/ 2];
    while (estimate > 180) {
      estimate /= 2;
    }
    tempo = estimate.round().clamp(30, 180);
  }

  final List<Json> notes;
  final String path, audioHash;
  final int durationMs;
  final String id = 'import-${uuid()}';
  String title;
  late int tempo;
  bool get folded => notes.map((note) => note['midi']).toSet().length > 16;

  PianoPiece build() {
    if (title.trim().isEmpty || tempo < 30 || tempo > 240 || notes.isEmpty) {
      throw const FormatException('Invalid imported song');
    }
    final fold = folded;
    int pitch(Json note) =>
        fold ? 60 + (note['midi'] as int) % 12 : note['midi'] as int;
    final midis = notes.map(pitch).toSet().toList()..sort();
    const white = [0, 2, 4, 5, 7, 9, 11];
    final steps = [
      for (final midi in midis)
        (midi ~/ 12 - 5) * 7 +
            white.lastIndexWhere((value) => value <= midi % 12),
    ];
    final score = <Json>[];
    var cursor = 0;
    for (final note in notes) {
      final start = ((note['start_ms'] as int) * tempo * 4 / 60000)
          .round()
          .clamp(cursor, 10000000);
      final end = ((note['end_ms'] as int) * tempo * 4 / 60000).round().clamp(
        start + 1,
        10000001,
      );
      if (start > cursor) {
        score.add({'note_index': -1, 'duration_ticks': start - cursor});
      }
      score.add({
        'note_index': midis.indexOf(pitch(note)),
        'duration_ticks': end - start,
      });
      cursor = end;
    }
    final audioEnd = (durationMs * tempo * 4 / 60000).ceil();
    final fullEnd = ((audioEnd > cursor ? audioEnd : cursor) / 16).ceil() * 16;
    if (fullEnd > cursor) {
      score.add({'note_index': -1, 'duration_ticks': fullEnd - cursor});
    }
    if (score.length > 4096) {
      throw const FormatException('Too many imported notes');
    }
    final data = normalizeRecordText({
      'schema_version': 1,
      'content_id': id,
      'version': 'local-mp3-1',
      'localized_title': {'zh-Hans': title.trim(), 'en': title.trim()},
      'localized_description': {
        'zh-Hans': '本地导入 · 自动识别单旋律',
        'en': 'Local import · estimated melody',
      },
      'ticks_per_beat': 4,
      'beats_per_bar': 4,
      'tempo_bpm': tempo,
      'key_steps': steps,
      'key_midis': midis,
      'notes': score,
      'import_method': 'local-yin-v1',
      'octave_folded': fold,
      'accompaniment': {
        'kind': 'local_mp3',
        'path': path,
        'sha256': audioHash,
        'base_tempo_bpm': tempo,
        'tempo_bpm': tempo,
        'duration_ms': durationMs,
        'sample_frames': durationMs * 22050 ~/ 1000,
        'total_ticks': fullEnd,
      },
    }) as Json;
    return PianoPiece.fromJson({...data, 'content_hash': digest(data)});
  }

  PianoPiece preview() {
    final piece = build();
    final preview = <Json>[];
    var remaining = 8 * piece.barTicks;
    for (final note in piece.notes.skipWhile((note) => note.isRest)) {
      if (remaining <= 0) break;
      final length = note.ticks.clamp(1, remaining);
      preview.add({'note_index': note.key, 'duration_ticks': length});
      remaining -= length;
    }
    final used = 8 * piece.barTicks - remaining;
    if (used % piece.barTicks != 0) {
      preview.add({
        'note_index': -1,
        'duration_ticks': piece.barTicks - used % piece.barTicks,
      });
    }
    final data = {...piece.data, 'notes': preview}
      ..remove('content_hash')
      ..remove('accompaniment');
    return PianoPiece.fromJson({...data, 'content_hash': digest(data)});
  }
}
