import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../domain/piano_piece.dart';

/// Recorded input is premixed on PianoAudio and played by the same Oboe stream.
class PieceReplayAudio {
  PieceReplayAudio(this.c, this.piece);
  final AppController c;
  final PianoPiece piece;
  String? _owner;
  int _revision = 0;
  bool closed = false;
  bool get audible => c.soundEnabled && c.audioReady;
  Future<void> prepare({
    required List<Json> notes,
    required int durationUs,
    required int tempo,
    required List<Json> segments,
    required bool backing,
    List<int> releaseCuts = const [],
  }) async {
    final revision = ++_revision;
    final previous = _owner;
    _owner = null;
    if (previous != null) {
      await c.platform.call('stopPieceBacking', {'owner': previous});
    }
    if (closed || revision != _revision || !audible) return;
    final owner = uuid();
    _owner = owner;
    final track = piece.accompanimentFor(tempo);
    await c.platform.call('preparePieceBacking', {
      'owner': owner,
      'tempo_bpm': tempo,
      'gain_permille': c.settings['gain_permille'],
      'replay_duration_us': durationUs,
      'solo': !backing || track == null,
      if (backing && track != null) ...{
        'path': track['path'],
        'sha256': track['sha256'],
        'sample_frames': track['sample_frames'],
      },
      'replay_segments': segments,
      'release_cuts': releaseCuts,
      'melody': [
        for (final n in notes)
          {
            'note_id': piece.playback(n['key'] as int).sample,
            'rate_permille': piece.playback(n['key'] as int).rate,
            'start_us': n['start_us'],
            'duration_us': n['duration_us'],
          },
      ],
    });
    if (closed || revision != _revision) {
      await c.platform.call('stopPieceBacking', {'owner': owner});
    }
  }

  Future<void> play(int position) async {
    if (_owner == null || !audible) return;
    final result = await c.platform.call('syncPieceBacking', {
      'owner': _owner,
      'position_us': position,
      'seek': true,
    });
    if (result['accepted'] != true) throw StateError('Replay owner expired');
  }

  Future<void> pause() async {
    if (_owner == null) return;
    await c.platform.call('pausePieceBacking', {'owner': _owner});
  }

  Future<int?> position() async {
    if (_owner == null || !audible) return null;
    final data = await c.platform.call('getPieceClock', {'owner': _owner});
    if (data['accepted'] == false) throw StateError('Replay interrupted');
    return data['running'] == true ? data['position_us'] as int? : null;
  }

  Future<void> stop() async {
    ++_revision;
    final owner = _owner;
    _owner = null;
    if (owner != null) {
      await c.platform.call('stopPieceBacking', {'owner': owner});
    }
  }

  void close() {
    closed = true;
    stop().catchError((_) {});
  }
}
