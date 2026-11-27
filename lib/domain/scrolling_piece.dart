import 'contracts.dart';
import 'piano_piece.dart';
import 'piece_trace.dart';
import 'piece_timing.dart';

enum ScrollPieceMode { ready, running, paused, complete }

/// Musical timeline with optional beginner gates at unplayed note onsets.
class ScrollingPiecePlayer {
  ScrollingPiecePlayer(
    this.piece,
    this.clock, {
    required this.tempo,
    this.training = false,
    this.practiceMode = PiecePracticeMode.continuous,
  }) {
    if (tempo < 30 || tempo > 240 || (training && tempo > piece.tempo)) {
      throw ArgumentError.value(tempo, 'tempo');
    }
  }
  final PianoPiece piece;
  final Clock clock;
  final int tempo;
  final bool training;
  final PiecePracticeMode practiceMode;
  final _claimed = <int>{};
  final _pressClocks = <int, int>{};
  int? _waitingIndex, _waitingSince;
  bool get waitingForKey => _waitingIndex != null;
  int get waitDurationUs =>
      _waitingSince == null ? 0 : clock.now - _waitingSince!;
  int noteEndUs(int index) => training
      ? PieceTiming.endUs(piece, index, tempo)
      : atTick(piece.notes[index].endTick);
  bool holdingNote(int index) => pointers.entries.any(
    (entry) =>
        entry.value.noteIndex == index &&
        (!training || trace.held[entry.key]?['judgement'] == 'holding'),
  );
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
    if (mode != ScrollPieceMode.running || waitingForKey) return;
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
  void start({int leadBeats = 4, int? leadUs}) {
    if (leadBeats < 0 || leadBeats > 4) throw ArgumentError('Invalid lead in');
    if (leadUs != null && (leadUs < 0 || leadUs > 8000000)) {
      throw ArgumentError('Invalid count-in');
    }
    elapsedUs = -(leadUs ?? atTick(leadBeats * piece.ticksPerBeat));
    _anchor = clock.now - elapsedUs;
    trace.reset();
    pointers.clear();
    matchedNotes.clear();
    wrongPresses = 0;
    _claimed.clear();
    _pressClocks.clear();
    _waitingIndex = _waitingSince = null;
    mode = ScrollPieceMode.running;
  }

  void tick() {
    if (mode != ScrollPieceMode.running) return;
    if (waitingForKey) return;
    final previous = elapsedUs;
    elapsedUs = clock.now - _anchor;
    if (training && practiceMode == PiecePracticeMode.beginner) {
      for (var i = 0; i < piece.notes.length; i++) {
        final note = piece.notes[i];
        final onset = atTick(note.startTick);
        if (!note.isRest &&
            !_claimed.contains(i) &&
            onset >= previous &&
            onset <= elapsedUs) {
          elapsedUs = onset;
          for (final pointer in pointers.keys.toList()) {
            _finishPress(pointer, 'late_release');
          }
          trace.pause(elapsedUs);
          _waitingIndex = i;
          _waitingSince = clock.now;
          return;
        }
      }
    }
    if (training) {
      for (final entry in pointers.entries) {
        final index = entry.value.noteIndex;
        final press = trace.held[entry.key];
        if (index != null &&
            press != null &&
            press['judgement'] == 'holding' &&
            elapsedUs > noteEndUs(index) + PieceTiming.releaseToleranceUs) {
          press['judgement'] = 'late_release';
          press['success'] = false;
          wrongPresses++;
        }
      }
    }
    if (elapsedUs >= totalUs && (!training || pointers.isEmpty)) {
      if (!training) elapsedUs = totalUs;
      trace.complete(elapsedUs);
      pointers.clear();
      mode = ScrollPieceMode.complete;
    }
  }

  bool down(int id, int key) {
    tick();
    if (training) return _trainingDown(id, key);
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
    if (training) {
      _finishPress(id);
      return;
    }
    trace.up(id, elapsedUs.clamp(0, totalUs));
    pointers.remove(id);
  }

  void soundOff(int id) => trace.soundOff(id, elapsedUs.clamp(0, totalUs));

  int? _nearestNote(int key, {required bool matchingKey}) {
    int? selected;
    var distance = PieceTiming.onsetToleranceUs + 1;
    for (var i = 0; i < piece.notes.length; i++) {
      final note = piece.notes[i];
      if (note.isRest ||
          _claimed.contains(i) ||
          (matchingKey && note.key != key)) {
        continue;
      }
      final delta = (elapsedUs - atTick(note.startTick)).abs();
      if (delta < distance) {
        selected = i;
        distance = delta;
      }
    }
    return selected;
  }

  bool _trainingDown(int id, int key) {
    if (mode != ScrollPieceMode.running ||
        key < 0 ||
        key >= piece.keyCount ||
        elapsedUs < -PieceTiming.onsetToleranceUs) {
      return false;
    }
    if (pointers.containsKey(id)) _finishPress(id, 'interrupted');
    final duplicate = pointers.values.any((p) => p.key == key);
    final index = duplicate ? null : _nearestNote(key, matchingKey: true);
    final expected =
        index ?? _nearestNote(key, matchingKey: false) ?? currentIndex;
    final waited = waitDurationUs;
    if (waitingForKey && index == _waitingIndex) {
      trace.resume(elapsedUs);
      _waitingIndex = _waitingSince = null;
      _anchor = clock.now - elapsedUs;
    }
    trace.down(
      id,
      key,
      elapsedUs.clamp(0, 86400000000),
      index == null ? null : piece.soundingIndex(index),
    );
    final press = trace.held[id];
    if (press == null) return false;
    press.addAll({
      'success': false,
      'judgement': index == null ? 'wrong_key_or_timing' : 'holding',
      'expected_note': expected,
      'onset_offset_us': expected == null
          ? null
          : elapsedUs - atTick(piece.notes[expected].startTick),
      'release_offset_us': null,
      'hold_duration_us': 0,
      'waiting_us': waited,
    });
    _pressClocks[id] = clock.now;
    pointers[id] = (key: key, noteIndex: index);
    if (index == null) {
      wrongPresses++;
    } else {
      _claimed.add(index);
    }
    return true;
  }

  void _finishPress(int id, [String? failure]) {
    final press = trace.held[id];
    final pointer = pointers[id];
    if (press == null || pointer == null) {
      pointers.remove(id);
      _pressClocks.remove(id);
      return;
    }
    final index = pointer.noteIndex;
    press['hold_duration_us'] = clock.now - (_pressClocks[id] ?? clock.now);
    if (index != null) {
      final offset = elapsedUs - noteEndUs(index);
      press['release_offset_us'] = offset;
      if (press['judgement'] == 'holding') {
        final result =
            failure ??
            (offset < -PieceTiming.releaseToleranceUs
                ? 'early_release'
                : offset > PieceTiming.releaseToleranceUs
                ? 'late_release'
                : 'success');
        press['judgement'] = result;
        press['success'] = result == 'success';
        if (result == 'success') {
          matchedNotes.add(piece.soundingIndex(index));
        } else {
          wrongPresses++;
        }
      }
    }
    trace.up(id, elapsedUs.clamp(0, 86400000000));
    pointers.remove(id);
    _pressClocks.remove(id);
  }

  void pause() {
    if (mode != ScrollPieceMode.running) return;
    tick();
    if (mode != ScrollPieceMode.running) return;
    if (training) {
      for (final pointer in pointers.keys.toList()) {
        _finishPress(pointer, 'interrupted');
      }
    }
    trace.pause(elapsedUs);
    pointers.clear();
    mode = ScrollPieceMode.paused;
  }

  void resume() {
    if (mode != ScrollPieceMode.paused) return;
    if (!waitingForKey) trace.resume(elapsedUs);
    _anchor = clock.now - elapsedUs;
    mode = ScrollPieceMode.running;
  }
}
