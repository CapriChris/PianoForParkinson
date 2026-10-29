import 'dart:convert';
import 'dart:io';

import 'package:piano_practice/domain/contracts.dart';

void main() {
  const keys = [
    2,
    2,
    3,
    4,
    4,
    3,
    2,
    1,
    0,
    0,
    1,
    2,
    2,
    1,
    1,
    2,
    2,
    3,
    4,
    4,
    3,
    2,
    1,
    0,
    0,
    1,
    2,
    1,
    0,
    0,
  ];
  // Transpose the first eight soprano bars of the cited score from G to C.
  // Each phrase ends with a dotted quarter, an eighth and a half note.
  final ticks = [
    for (var phrase = 0; phrase < 2; phrase++) ...[
      ...List.filled(12, 2),
      3,
      1,
      4,
    ],
  ];
  final piece = <String, dynamic>{
    'schema_version': 1,
    'content_id': 'piece-ode-to-joy-001',
    'legacy_song_ids': ['song-ode-to-joy-001'],
    'version': '1.0.0',
    'localized_title': {'zh-Hans': '欢乐颂', 'en': 'Ode to Joy'},
    'localized_description': {
      'zh-Hans': '贝多芬 · 主题前两句 · 五键 · 8 小节',
      'en': 'Beethoven · Opening two phrases · Five keys · 8 bars',
    },
    'ticks_per_beat': 2,
    'beats_per_bar': 4,
    'tempo_bpm': 60,
    'notes': [
      for (var i = 0; i < keys.length; i++)
        {'note_index': keys[i], 'duration_ticks': ticks[i]},
    ],
    'source': {
      'composer': 'Ludwig van Beethoven',
      'work': 'Symphony No. 9, Op. 125, finale theme',
      'score': 'https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode-let.pdf',
      'notation': 'https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.ly',
      'adaptation': 'Opening 8 bars of soprano melody transposed from G to C; original note durations retained. Peter Chubb typesetting, Mutopia-2009/08/05-528, public domain.',
      'recording': 'Salamander Grand Piano V3, Alexander Holm, CC BY 3.0; see piano_attribution.txt',
    },
  };
  piece['content_hash'] = digest(piece);
  const path = 'assets/content/piece-ode-to-joy-001.json';
  File(
    path,
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(piece)}\n');
  final catalogFile = File('assets/content/piece-catalog.json');
  final previous = catalogFile.existsSync()
      ? jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  catalogFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schema_version': 1,
      'paths': {path, ...((previous['paths'] as List?)?.cast<String>() ?? <String>[])}.toList(),
    })}\n',
  );
}
