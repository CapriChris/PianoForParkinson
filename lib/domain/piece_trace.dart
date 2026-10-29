import 'contracts.dart';
import 'piano_piece.dart';

/// Actual input intervals plus pause spans; independent of score matching.
class PieceTraceRecorder {
  PieceTraceRecorder(this.piece, this.clock);
  final PianoPiece piece;
  final Clock clock;
  final notes = <Json>[], pauses = <Json>[];
  final held = <int, Json>{};
  int? _pauseWall, _pauseClock;
  int _pausedUs = 0;
  bool truncated = false, finished = false;
  int lastScore = 0, lastWall = 0;
  void reset() {
    notes.clear();
    pauses.clear();
    held.clear();
    _pauseWall = _pauseClock = null;
    _pausedUs = 0;
    truncated = finished = false;
    lastScore = lastWall = 0;
  }

  int wall(int scoreUs) {
    final duringPause = _pauseClock == null
        ? 0
        : (clock.now - _pauseClock!).clamp(0, 86400000000);
    final now = (scoreUs + _pausedUs + duringPause).clamp(
      lastWall,
      86400000000,
    );
    lastWall = now;
    return now;
  }

  int position(int scoreUs) {
    lastScore = scoreUs.clamp(lastScore, 3600000000);
    return lastScore;
  }

  void down(int pointer, int key, int scoreUs, int? noteIndex) {
    if (finished || scoreUs < 0) return;
    up(pointer, scoreUs);
    final at = position(scoreUs), atWall = wall(at);
    if (notes.length >= 8192) {
      truncated = true;
      return;
    }
    final n = <String, dynamic>{
      'key': key,
      'start_us': at,
      'wall_start_us': atWall,
      'end_us': at,
      'wall_end_us': atWall,
      'touch_end_us': at,
      'touch_wall_end_us': atWall,
      'matched_note': noteIndex,
    };
    notes.add(n);
    held[pointer] = n;
  }

  void soundOff(int pointer, int scoreUs) {
    final n = held[pointer];
    if (n == null || n['sound_closed'] == true) return;
    n['end_us'] = position(scoreUs);
    n['wall_end_us'] = wall(lastScore);
    n['sound_closed'] = true;
  }

  void up(int pointer, int scoreUs) {
    final n = held[pointer];
    if (n == null) return;
    soundOff(pointer, scoreUs);
    n['touch_end_us'] = position(scoreUs);
    n['touch_wall_end_us'] = wall(lastScore);
    held.remove(pointer);
  }

  void closeHeld(int scoreUs) {
    for (final pointer in held.keys.toList()) {
      up(pointer, scoreUs);
    }
  }

  void pause(int scoreUs) {
    if (finished || scoreUs < 0 || _pauseWall != null) return;
    position(scoreUs);
    closeHeld(lastScore);
    _pauseWall = wall(lastScore);
    _pauseClock = clock.now;
  }

  void resume(int scoreUs) {
    if (_pauseWall == null) return;
    final end = wall(lastScore);
    if (pauses.length < 1024) {
      pauses.add({
        'score_us': lastScore,
        'start_us': _pauseWall,
        'end_us': end,
      });
    } else {
      truncated = true;
    }
    _pausedUs += end - _pauseWall!;
    _pauseWall = _pauseClock = null;
  }

  Json complete(int totalUs) {
    if (!finished) {
      resume(totalUs);
      closeHeld(totalUs);
      position(totalUs);
      wall(totalUs);
      finished = true;
    }
    return {
      'version': 1,
      'duration_us': lastWall < totalUs ? totalUs : lastWall,
      'truncated': truncated,
      'notes': [
        for (final n in notes) {...n}..remove('sound_closed'),
      ],
      'pauses': [
        for (final p in pauses) {...p},
      ],
    };
  }
}

/// Exact score and replay time conversion, including original pauses.
class PieceReviewData {
  PieceReviewData(this.record, this.piece);
  final Json record;
  final PianoPiece piece;
  Json? get trace => record['performance_trace'] as Json?;
  bool get canReplay => trace != null;
  bool get truncated => trace?['truncated'] == true;
  int get scoreDuration => record['duration_us'] as int;
  int get wallDuration => trace?['duration_us'] as int? ?? scoreDuration;
  late final List<Json> pauses = List<Json>.from(
    trace?['pauses'] as List? ?? [],
  );
  late final List<Json> touches = List<Json>.from(
    trace?['notes'] as List? ?? [],
  );
  int tickUs(int tick) =>
      tick * 60000000 ~/ ((record['tempo_bpm'] as int) * piece.ticksPerBeat);
  int scoreAt(int position, {required bool preservePauses}) {
    if (!preservePauses) return position.clamp(0, scoreDuration);
    var offset = 0;
    for (final pause in pauses) {
      if (position < pause['start_us']) break;
      if (position < pause['end_us']) return pause['score_us'] as int;
      offset += (pause['end_us'] as int) - (pause['start_us'] as int);
    }
    return (position - offset).clamp(0, scoreDuration);
  }

  int wallAt(int scoreUs) {
    var offset = 0;
    for (final pause in pauses) {
      if (pause['score_us'] > scoreUs) break;
      offset += (pause['end_us'] as int) - (pause['start_us'] as int);
    }
    return (scoreUs + offset).clamp(0, wallDuration);
  }

  List<Json> segments(bool preservePauses) {
    if (!preservePauses) {
      return [
        {'target_us': 0, 'source_us': 0, 'duration_us': scoreDuration},
      ];
    }
    final result = <Json>[];
    var score = 0, target = 0;
    for (final pause in pauses) {
      final length = (pause['score_us'] as int) - score;
      if (length > 0) {
        result.add({
          'target_us': target,
          'source_us': score,
          'duration_us': length,
        });
      }
      score = pause['score_us'] as int;
      target = pause['end_us'] as int;
    }
    if (score < scoreDuration) {
      result.add({
        'target_us': target,
        'source_us': score,
        'duration_us': scoreDuration - score,
      });
    }
    return result;
  }

  List<Json> replayNotes(bool preservePauses) => [
    for (final n in touches)
      if (n[preservePauses ? 'wall_end_us' : 'end_us'] >
          n[preservePauses ? 'wall_start_us' : 'start_us'])
        {
          'key': n['key'],
          'start_us': n[preservePauses ? 'wall_start_us' : 'start_us'],
          'duration_us':
              n[preservePauses ? 'wall_end_us' : 'end_us'] -
              n[preservePauses ? 'wall_start_us' : 'start_us'],
        },
  ];
  List<Json> demoNotes() => _demoNotes;
  late final List<Json> _demoNotes = [
    for (final n in piece.notes)
      if (!n.isRest)
        {
          'key': n.key,
          'start_us': tickUs(n.startTick),
          'duration_us': tickUs(n.endTick) - tickUs(n.startTick),
        },
  ];
}
