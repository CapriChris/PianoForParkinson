import 'contracts.dart';
import 'piano_piece.dart';
import 'piece_trace.dart';

enum ScrollPieceMode { ready, running, paused, complete }

/// A fixed musical timeline. Missed or short notes never stop the score.
class ScrollingPiecePlayer {
  ScrollingPiecePlayer(this.piece, this.clock, {required this.tempo}) {
    if (![40, 50, 60, 70, 80].contains(tempo)) {
      throw ArgumentError.value(tempo, 'tempo');
    }
  }
  final PianoPiece piece;
  final Clock clock;
  final int tempo;
  late final trace = PieceTraceRecorder(piece, clock);
  ScrollPieceMode mode = ScrollPieceMode.ready;
  int elapsedUs = 0, _anchor = 0;
  final matchedNotes = <int>{};
  int wrongPresses = 0;
  final pointers = <int, ({int key, int? noteIndex})>{};
  int atTick(int tick) => tick * 60000000 ~/ (tempo * piece.ticksPerBeat);
  int get totalUs => atTick(piece.ticks);
  double get positionTick => elapsedUs * tempo * piece.ticksPerBeat / 60000000;

  /// Native presentation time is the master; interpolate between observations.
  void followAudioPosition(int positionUs) {
    if (mode != ScrollPieceMode.running) return;
    final predicted = clock.now - _anchor;
    final error = positionUs - predicted;
    // Large corrections cover stream startup; smaller corrections avoid visible
    // jitter from the platform round trip while keeping the clocks together.
    final correction = error.abs() > 100000 ? error : (error * .3).round();
    _anchor -= correction;
  }

  bool get leadingIn => mode != ScrollPieceMode.complete && elapsedUs < 0;
  int? get currentIndex {
    if (elapsedUs < 0 || elapsedUs >= totalUs) return null;
    for (var i = 0; i < piece.notes.length; i++) {
      if (elapsedUs < atTick(piece.notes[i].endTick)) return i;
    }
    return null;
  }

  int? get targetKey =>
      currentIndex == null || piece.notes[currentIndex!].isRest
      ? null
      : piece.notes[currentIndex!].key;
  bool get targetPressed =>
      currentIndex != null &&
      pointers.values.any(
        (p) => p.noteIndex == currentIndex && p.key == targetKey,
      );
  void start({int leadBeats = 4}) {
    if (leadBeats < 0 || leadBeats > 4) throw ArgumentError('Invalid lead in');
    elapsedUs = -atTick(leadBeats * piece.ticksPerBeat);
    _anchor = clock.now - elapsedUs;
    trace.reset();
    pointers.clear();
    matchedNotes.clear();
    wrongPresses = 0;
    mode = ScrollPieceMode.running;
  }

  void tick() {
    if (mode != ScrollPieceMode.running) return;
    elapsedUs = clock.now - _anchor;
    if (elapsedUs >= totalUs) {
      elapsedUs = totalUs;
      trace.complete(totalUs);
      pointers.clear();
      mode = ScrollPieceMode.complete;
    }
  }

  bool down(int id, int key) {
    tick();
    if (mode != ScrollPieceMode.running ||
        leadingIn ||
        targetKey == null ||
        key < 0 ||
        key >= piece.keyCount) {
      return false;
    }
    trace.down(
      id,
      key,
      elapsedUs,
      targetKey == key ? piece.soundingIndex(currentIndex!) : null,
    );
    pointers[id] = (
      key: key,
      noteIndex: targetKey == key ? currentIndex : null,
    );
    if (targetKey == key) {
      matchedNotes.add(piece.soundingIndex(currentIndex!));
    } else {
      wrongPresses++;
    }
    return true;
  }

  void up(int id) {
    tick();
    trace.up(id, elapsedUs.clamp(0, totalUs));
    pointers.remove(id);
  }

  void soundOff(int id) => trace.soundOff(id, elapsedUs.clamp(0, totalUs));
  void pause() {
    if (mode != ScrollPieceMode.running) return;
    tick();
    if (mode != ScrollPieceMode.running) return;
    trace.pause(elapsedUs);
    pointers.clear();
    mode = ScrollPieceMode.paused;
  }

  void resume() {
    if (mode != ScrollPieceMode.paused) return;
    trace.resume(elapsedUs);
    _anchor = clock.now - elapsedUs;
    mode = ScrollPieceMode.running;
  }
}
