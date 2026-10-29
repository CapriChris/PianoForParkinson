import 'dart:convert';
import 'dart:io';

import 'package:piano_practice/domain/contracts.dart';

void main() {
  final original =
      jsonDecode(File('assets/content/song.json').readAsStringSync()) as Json;
  final paths = ['assets/content/song.json'];
  for (final entry in [
    ('song-original-002', '上行与回声', 'Rise and Echo', [0, 1, 2, 1, 0, 2, 3, 4]),
    ('song-original-003', '缓缓回落', 'Gentle Descent', [4, 3, 2, 1, 0, 1, 2, 0]),
  ]) {
    final song = <String, dynamic>{
      'content_id': entry.$1,
      'version': '1.0.0',
      'category': 'ORIGINAL_EXERCISE',
      'localized_title': {'zh-Hans': entry.$2, 'en': entry.$3},
      'notes': [
        for (final note in entry.$4) {'note_index': note, 'duration_ms': 400},
      ],
      'tempo_bpm': 40,
      'supported_tasks': ['S1_GUIDED', 'S2_RHYTHM'],
      'rights': {
        'status': 'DEVELOPMENT_ONLY',
        'melody': 'Project original exercise sequence, 2026-10-18',
        'arrangement': 'Project original',
        'recording': original['rights']['recording'],
      },
      'assets': original['assets'],
    };
    song['content_hash'] = digest(song);
    final path = 'assets/content/${entry.$1}.json';
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(song)}\n',
    );
    paths.add(path);
  }
  File('assets/content/catalog.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'schema_version': 1, 'paths': paths})}\n',
  );
}
