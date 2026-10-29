import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';
import '../domain/piano_piece.dart';
import 'record_integrity.dart';

class ContentRepository {
  static bool _pianoLicenseRegistered = false;
  late PracticeConfig config;
  late Json song, soundPack;
  List<Json> songs = [];
  List<PianoPiece> pieces = [];
  PianoPiece? pieceFor(String? id) {
    if (id == null) return null;
    for (final piece in pieces) {
      if (piece.id == id ||
          (piece.data['legacy_song_ids'] as List? ?? const []).contains(id)) {
        return piece;
      }
    }
    return null;
  }

  List<Json> songsFor(String taskId) => songs
      .where((item) => (item['supported_tasks'] as List).contains(taskId))
      .toList();
  void select(String? id) {
    song = songs.firstWhere(
      (item) => item['content_id'] == id,
      orElse: () => songs.first,
    );
  }

  Future<void> load() async {
    config = PracticeConfig(
      jsonDecode(await rootBundle.loadString('assets/config/demo.json'))
          as Json,
    );
    RecordIntegrity.configuration(config.json);
    final catalog = jsonDecode(
      await rootBundle.loadString('assets/content/catalog.json'),
    ) as Json;
    if (catalog['schema_version'] != 1) {
      throw const FormatException('Invalid catalog');
    }
    songs = [];
    final ids = <String>{};
    for (final path in catalog['paths'] as List) {
      if (path is! String ||
          !RegExp(r'^assets/content/[a-z0-9_-]+\.json$').hasMatch(path)) {
        throw const FormatException('Invalid content path');
      }
      final item = jsonDecode(await rootBundle.loadString(path)) as Json;
      final hashData = {...item}..remove('content_hash');
      if (item['content_hash'] != digest(hashData) ||
          item['rights']?['status'] != 'DEVELOPMENT_ONLY' ||
          !ids.add(item['content_id'] as String)) {
        throw const FormatException('Invalid content');
      }
      if (!(item['localized_title'] as Map).keys.toSet().containsAll([
        'zh-Hans',
        'en',
      ])) {
        throw const FormatException('Missing title');
      }
      final notes = item['notes'];
      if (notes is! List ||
          notes.length != 8 ||
          notes.any(
            (n) =>
                n['note_index'] is! int ||
                n['note_index'] < 0 ||
                n['note_index'] > 4 ||
                n['duration_ms'] != 400,
          )) {
        throw const FormatException('Invalid melody');
      }
      // Reject ambiguous normalized keys without changing the stored content hash.
      if (canonical(normalizeRecordText(item)) != canonical(item)) {
        throw const FormatException('Content must use NFC');
      }
      songs.add(item);
    }
    if (songs.isEmpty) throw const FormatException('Empty catalog');
    song = songs.first;
    final pieceCatalog = jsonDecode(
      await rootBundle.loadString('assets/content/piece-catalog.json'),
    ) as Json;
    if (pieceCatalog['schema_version'] != 1 || pieceCatalog['paths'] is! List) {
      throw const FormatException('Invalid piece catalog');
    }
    pieces = [];
    final pieceIds = <String>{};
    for (final path in pieceCatalog['paths'] as List) {
      if (path is! String ||
          !RegExp(r'^assets/content/piece-[a-z0-9_-]+\.json$').hasMatch(path)) {
        throw const FormatException('Invalid piece path');
      }
      final piece = PianoPiece.fromJson(
        jsonDecode(await rootBundle.loadString(path)) as Json,
      );
      if (!pieceIds.add(piece.id)) {
        throw const FormatException('Duplicate piece');
      }
      pieces.add(piece);
    }
    soundPack = jsonDecode(
      await rootBundle.loadString('assets/content/sound_pack.json'),
    ) as Json;
    if (!_pianoLicenseRegistered) {
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          'stb_vorbis',
        ], await rootBundle.loadString('assets/content/stb_license.txt'));
        yield LicenseEntryWithLineBreaks([
          'Oboe 1.11.0',
        ], await rootBundle.loadString('assets/content/oboe_license.txt'));
        yield LicenseEntryWithLineBreaks([
          'Salamander Grand Piano V3',
        ], await rootBundle.loadString('assets/content/piano_attribution.txt'));
        yield LicenseEntryWithLineBreaks(
          ['琴伴钢琴伴奏参考谱 / Piano accompaniment scores'],
          await rootBundle.loadString(
            'assets/content/backing_score_attribution.txt',
          ),
        );
      });
      _pianoLicenseRegistered = true;
    }
    final hashData = {...song}..remove('content_hash');
    if (song['content_hash'] != digest(hashData) ||
        song['rights']['status'] != 'DEVELOPMENT_ONLY') {
      throw const FormatException('Invalid development content');
    }
    if (!(song['localized_title'] as Map).keys.toSet().containsAll([
      'zh-Hans',
      'en',
    ])) {
      throw const FormatException('Missing content language');
    }
    for (final note in song['notes'] as List) {
      if (note['note_index'] is! int ||
          note['note_index'] < 0 ||
          note['note_index'] > 4 ||
          note['duration_ms'] != 400) {
        throw const FormatException('Invalid note');
      }
    }
    if ((soundPack['assets'] as List).length != 10) {
      throw const FormatException('Incomplete sound pack');
    }
    for (final asset in soundPack['assets'] as List) {
      final bytes = await rootBundle.load(asset['path'] as String);
      if (sha256
              .convert(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              )
              .toString() !=
          asset['sha256']) {
        throw const FormatException('Sound hash mismatch');
      }
    }
  }

  List<int> get notes =>
      (song['notes'] as List).map((n) => n['note_index'] as int).toList();
}
