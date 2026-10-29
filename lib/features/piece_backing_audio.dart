import 'dart:async';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../domain/piano_piece.dart';
import '../domain/scrolling_piece.dart';

/// Start a pre-rendered track once at the score position. Continuous audio must
/// never seek in response to delayed UI frames or coarse media position reports.
class PieceBackingAudio {
  PieceBackingAudio(
    this.c,
    this.piece, {
    required this.onError,
    this.audition = false,
  });
  final bool audition;
  final AppController c;
  final PianoPiece piece;
  final void Function() onError;
  String? _owner;
  int _revision = 0;
  bool _ready = false, _closed = false, _started = false;
  bool _clockPolling = false;
  int _lastPoll = -1000000;

  Future<void> prepare(int tempo) async {
    final revision = ++_revision;
    _ready = _started = false;
    final backing = piece.accompanimentFor(tempo);
    if (_closed || !c.soundEnabled || !c.audioReady || backing == null) return;
    final owner = uuid();
    _owner = owner;
    await c.platform.call('preparePieceBacking', {
      'owner': owner,
      'path': backing['path'],
      'sha256': backing['sha256'],
      'sample_frames': backing['sample_frames'],
      'tempo_bpm': tempo,
      'gain_permille': c.settings['gain_permille'],
      if (audition)
        'melody': [
          for (final note in piece.notes)
            if (!note.isRest)
              {
                'note_id': piece.playback(note.key).sample,
                'rate_permille': piece.playback(note.key).rate,
                'start_us':
                    note.startTick * 60000000 ~/ (tempo * piece.ticksPerBeat),
                'duration_us':
                    note.ticks * 60000000 ~/ (tempo * piece.ticksPerBeat),
              },
        ],
    });
    if (_closed || revision != _revision) {
      await c.platform.call('stopPieceBacking', {'owner': owner});
      return;
    }
    _ready = true;
  }

  Future<void> start(ScrollingPiecePlayer player) async {
    if (!_ready || _closed) return;
    final revision = _revision;
    final result = await c.platform.call('syncPieceBacking', {
      'owner': _owner,
      'position_us': player.elapsedUs,
    });
    if (revision != _revision || _closed) return;
    if (result['accepted'] != true) throw StateError('Audio timeline rejected');
    _started = true;
    _lastPoll = -1000000;
    sync(player);
  }

  void sync(ScrollingPiecePlayer player) {
    if (_ready &&
        !_closed &&
        _started &&
        player.mode == ScrollPieceMode.running &&
        !_clockPolling &&
        c.clock.now - _lastPoll >= 80000) {
      _clockPolling = true;
      _lastPoll = c.clock.now;
      final revision = _revision;
      final sentAt = c.clock.now;
      unawaited(
        c.platform
            .call('getPieceClock', {'owner': _owner})
            .then((data) {
              if (revision != _revision || _closed) return;
              if (data['accepted'] == false) {
                throw StateError('Stale audio clock');
              }
              if (data['running'] == true && data['position_us'] is int) {
                player.followAudioPosition(
                  (data['position_us'] as int) + (c.clock.now - sentAt) ~/ 2,
                );
              }
            })
            .catchError((Object _) {
              if (revision == _revision && !_closed) onError();
            })
            .whenComplete(() {
              _clockPolling = false;
            }),
      );
    }
  }

  Future<void> stop() async {
    ++_revision;
    _ready = _started = false;
    final owner = _owner;
    _owner = null;
    if (owner != null) {
      await c.platform.call('stopPieceBacking', {'owner': owner});
    }
  }

  void close() {
    _closed = true;
    unawaited(stop().catchError((_) {}));
  }
}
