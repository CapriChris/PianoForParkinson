import 'dart:convert';

import 'contracts.dart';
import 'scrolling_piece.dart';
import 'piano_piece.dart';

class PiecePerformance {
  static Json completed(ScrollingPiecePlayer player, DateTime started) {
    if (player.mode != ScrollPieceMode.complete) {
      throw StateError('E_PIECE_NOT_COMPLETE');
    }
    final piece = player.piece;
    return {
      'schema_version': 1,
      'session_id': uuid(),
      'content_id': piece.id,
      'content_hash': piece.data['content_hash'],
      'title_zh': piece.title('zh-Hans'),
      'title_en': piece.title('en'),
      'tempo_bpm': player.tempo,
      'started_utc_ms': started.toUtc().millisecondsSinceEpoch,
      'ended_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'session_utc_offset_minutes': started.timeZoneOffset.inMinutes,
      'duration_us': player.totalUs,
      'total_ticks': piece.ticks,
      if (piece.ticksPerBeat != 2) 'ticks_per_beat': piece.ticksPerBeat,
      'total_notes': piece.noteCount,
      if (piece.noteCount != piece.notes.length)
        'total_events': piece.notes.length,
      if (piece.beatsPerBar != 4) 'beats_per_bar': piece.beatsPerBar,
      if (piece.pickupTicks != 0) 'pickup_ticks': piece.pickupTicks,
      'matched_notes': player.matchedNotes.toList()..sort(),
      'wrong_presses': player.wrongPresses,
      'score_snapshot': jsonDecode(canonical(piece.data)),
      'performance_trace': player.trace.complete(player.totalUs),
    };
  }

  static void validate(Json record) {
    void require(bool value) {
      if (!value) throw const FormatException('E_PIECE_RECORD');
    }

    require(record['schema_version'] == 1);
    for (final field in ['session_id', 'content_id', 'title_zh', 'title_en']) {
      require(record[field] is String && (record[field] as String).isNotEmpty);
    }
    require(
      record['content_hash'] is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(record['content_hash'] as String),
    );
    for (final field in [
      'tempo_bpm',
      'started_utc_ms',
      'ended_utc_ms',
      'session_utc_offset_minutes',
      'duration_us',
      'total_ticks',
      'total_notes',
      'wrong_presses',
    ]) {
      require(record[field] is int);
    }
    require([40, 50, 60, 70, 80].contains(record['tempo_bpm']));
    require(
      record['started_utc_ms'] >= 0 &&
          record['ended_utc_ms'] >= record['started_utc_ms'],
    );
    require((record['session_utc_offset_minutes'] as int).abs() <= 840);
    require(record['total_notes'] > 0 && record['total_notes'] <= 512);
    final eventCount = record['total_events'] ?? record['total_notes'];
    final beatsPerBar = record['beats_per_bar'] ?? 4;
    final pickup = record['pickup_ticks'] ?? 0;
    require(
      eventCount is int &&
          eventCount >= record['total_notes'] &&
          eventCount <= 512,
    );
    require([3, 4].contains(beatsPerBar));
    final resolution = record['ticks_per_beat'] ?? 2;
    require([2, 4].contains(resolution));
    final barTicks = (beatsPerBar as int) * (resolution as int);
    require(pickup is int && pickup >= 0 && pickup < barTicks);
    require(
      record['total_ticks'] >= eventCount &&
          record['total_ticks'] <= eventCount * resolution * 16 &&
          (record['total_ticks'] % barTicks == 0 ||
              (record['total_ticks'] - pickup) % barTicks == 0),
    );
    require(
      record['duration_us'] ==
          record['total_ticks'] *
              60000000 ~/
              (record['tempo_bpm'] * resolution),
    );
    require(record['wrong_presses'] >= 0);
    final matched = record['matched_notes'];
    require(matched is List);
    require(
      (matched as List).every(
        (n) => n is int && n >= 0 && n < record['total_notes'],
      ),
    );
    require(matched.toSet().length == matched.length);
    if (record.containsKey('score_snapshot') ||
        record.containsKey('performance_trace')) {
      require(
        record['score_snapshot'] is Map && record['performance_trace'] is Map,
      );
      final piece = PianoPiece.fromJson(
        Map<String, dynamic>.from(record['score_snapshot'] as Map),
      );
      require(
        piece.id == record['content_id'] &&
            piece.data['content_hash'] == record['content_hash'],
      );
      require(
        piece.noteCount == record['total_notes'] &&
            piece.ticks == record['total_ticks'],
      );
      final trace = record['performance_trace'] as Map;
      require(trace['version'] == 1 && trace['truncated'] is bool);
      require(
        trace['duration_us'] is int &&
            trace['duration_us'] >= record['duration_us'] &&
            trace['duration_us'] <= 86400000000,
      );
      require(
        trace['notes'] is List && (trace['notes'] as List).length <= 8192,
      );
      require(
        trace['pauses'] is List && (trace['pauses'] as List).length <= 1024,
      );
      var previousStart = 0, previousWall = 0;
      for (final n in trace['notes'] as List) {
        require(n is Map);
        for (final field in [
          'key',
          'start_us',
          'end_us',
          'wall_start_us',
          'wall_end_us',
          'touch_end_us',
          'touch_wall_end_us',
        ]) {
          require(n[field] is int);
        }
        require(n['key'] >= 0 && n['key'] < piece.keyCount);
        require(
          n['start_us'] >= previousStart &&
              n['start_us'] <= n['end_us'] &&
              n['end_us'] <= n['touch_end_us'] &&
              n['touch_end_us'] <= record['duration_us'],
        );
        require(
          n['wall_start_us'] >= previousWall &&
              n['wall_start_us'] <= n['wall_end_us'] &&
              n['wall_end_us'] <= n['touch_wall_end_us'] &&
              n['touch_wall_end_us'] <= trace['duration_us'],
        );
        require(
          n['matched_note'] == null ||
              n['matched_note'] is int &&
                  n['matched_note'] >= 0 &&
                  n['matched_note'] < piece.noteCount,
        );
        previousStart = n['start_us'];
        previousWall = n['wall_start_us'];
      }
      var pauseEnd = 0, pauseScore = 0;
      for (final p in trace['pauses'] as List) {
        require(
          p is Map &&
              p['score_us'] is int &&
              p['start_us'] is int &&
              p['end_us'] is int,
        );
        require(
          p['score_us'] >= pauseScore && p['score_us'] <= record['duration_us'],
        );
        require(
          p['start_us'] >= pauseEnd &&
              p['end_us'] >= p['start_us'] &&
              p['end_us'] <= trace['duration_us'],
        );
        pauseEnd = p['end_us'];
        pauseScore = p['score_us'];
      }
    }
    require(canonical(normalizeRecordText(record)) == canonical(record));
  }

  static Json fromRow(Json row) {
    final record = jsonDecode(row['record_json'] as String) as Json;
    validate(record);
    if (row['record_hash'] != digest(record) ||
        [
          'session_id',
          'content_id',
          'started_utc_ms',
          'ended_utc_ms',
          'session_utc_offset_minutes',
        ].any((key) => row[key] != record[key])) {
      throw const FormatException('E_PIECE_RECORD');
    }
    return record;
  }

  static Json historyRow(Json row) => {
    ...row,
    'task_id': 'PIANO_PIECE',
    'status': 'COMPLETED',
    'result_json': canonical(fromRow(row)),
  };
}
