import 'dart:async';

import '../app/app_controller.dart';
import '../domain/piano_piece.dart';

/// Shared sample playback for the preparation preview and the scrolling page.
class PieceAudio {
  PieceAudio(this.c, {required this.onError, this.piece});
  final PianoPiece? piece;
  final AppController c;
  final void Function() onError;
  Future<void> _writes = Future.value();
  int _epoch = 0;
  bool _closed = false;
  void note(int key, bool down, int pointer) {
    final epoch = _epoch;
    _writes = _writes.catchError((_) {}).then((_) async {
      if (_closed || epoch != _epoch) return;
      try {
        final voice = piece?.playback(key) ?? (sample: key, rate: 1000);
        await c.preview(
          voice.sample,
          down,
          pointer: pointer,
          ratePermille: voice.rate,
        );
      } catch (_) {
        if (!_closed && epoch == _epoch) onError();
      }
    });
  }

  Future<void> stop() {
    ++_epoch;
    return c.stopAllPlayback();
  }

  void close() {
    _closed = true;
    unawaited(stop().catchError((_) {}));
  }
}
