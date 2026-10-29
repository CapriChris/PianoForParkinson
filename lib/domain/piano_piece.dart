import 'dart:math' as math;

import 'contracts.dart';

class PieceNote {
  const PieceNote(
    this.key,
    this.ticks,
    this.startTick, [
    this.ticksPerBeat = 2,
  ]);
  final int ticksPerBeat;
  final int key, ticks, startTick;
  bool get isRest => key < 0;
  int get endTick => startTick + ticks;
  String get beats => ticks % ticksPerBeat == 0
      ? '${ticks ~/ ticksPerBeat}'
      : '${ticks / ticksPerBeat}';
  String name(bool zh) => isRest
      ? (zh ? '休止符' : 'Rest')
      : switch (ticks * 2 / ticksPerBeat) {
          .5 => zh ? '十六分音符' : 'Sixteenth note',
          1 => zh ? '八分音符' : 'Eighth note',
          2 => zh ? '四分音符' : 'Quarter note',
          3 => zh ? '附点四分音符' : 'Dotted quarter note',
          4 => zh ? '二分音符' : 'Half note',
          6 => zh ? '附点二分音符' : 'Dotted half note',
          8 => zh ? '全音符' : 'Whole note',
          _ => zh ? '延长音' : 'Sustained note',
        };
}

class PianoPiece {
  PianoPiece.fromJson(Json json) : data = json {
    final hashData = {...json}..remove('content_hash');
    if (json['schema_version'] != 1 ||
        ![2, 4].contains(json['ticks_per_beat']) ||
        ![3, 4].contains(json['beats_per_bar']) ||
        json['content_hash'] != digest(hashData) ||
        json['tempo_bpm'] is! int ||
        ![40, 50, 60, 70, 80].contains(json['tempo_bpm']) ||
        canonical(normalizeRecordText(json)) != canonical(json)) {
      throw const FormatException('Invalid piano piece');
    }
    final steps = json['key_steps'] ?? [0, 1, 2, 3, 4];
    if (steps is! List ||
        steps.length < 2 ||
        steps.length > 16 ||
        steps.any((s) => s is! int || s < -14 || s > 21) ||
        (json['key_midis'] == null && steps.toSet().length != steps.length) ||
        (json['pickup_ticks'] ?? 0) is! int ||
        pickupTicks < 0 ||
        pickupTicks >= barTicks) {
      throw const FormatException('Invalid piece keyboard or pickup');
    }
    for (var i = 1; i < steps.length; i++) {
      if (steps[i] < steps[i - 1] ||
          (steps[i] == steps[i - 1] && json['key_midis'] == null)) {
        throw const FormatException('Unordered keyboard');
      }
    }
    final midis = json['key_midis'];
    if (midis != null) {
      if (midis is! List ||
          midis.length != steps.length ||
          midis.any((n) => n is! int || n < 36 || n > 96) ||
          midis.toSet().length != midis.length) {
        throw const FormatException('Invalid keyboard pitches');
      }
      for (var i = 1; i < midis.length; i++) {
        if (midis[i] <= midis[i - 1]) {
          throw const FormatException('Unordered pitches');
        }
      }
    }
    for (final field in ['localized_title', 'localized_description']) {
      final values = json[field];
      if (values is! Map ||
          ['zh-Hans', 'en'].any(
            (locale) =>
                values[locale] is! String || (values[locale] as String).isEmpty,
          )) {
        throw const FormatException('Missing piece text');
      }
    }
    if (json['content_id'] is! String ||
        json['notes'] is! List ||
        (json['notes'] as List).isEmpty ||
        (json['notes'] as List).length > 512) {
      throw const FormatException('Invalid piece notes');
    }
    var start = 0;
    final parsed = <PieceNote>[];
    for (final note in json['notes'] as List) {
      if (note is! Map ||
          note['note_index'] is! int ||
          note['note_index'] < -1 ||
          note['note_index'] >= keyCount ||
          note['duration_ticks'] is! int ||
          note['duration_ticks'] < 1 ||
          note['duration_ticks'] > ticksPerBeat * 16) {
        throw const FormatException('Invalid piece note');
      }
      parsed.add(
        PieceNote(
          note['note_index'],
          note['duration_ticks'],
          start,
          ticksPerBeat,
        ),
      );
      start += note['duration_ticks'] as int;
    }
    if ((start % barTicks != 0 && (start - pickupTicks) % barTicks != 0) ||
        parsed.every((n) => n.isRest)) {
      throw const FormatException('Incomplete piece bar');
    }
    notes = List.unmodifiable(parsed);
    final backing = json['accompaniment'];
    if (backing != null &&
        (backing is! Map ||
            backing['path'] is! String ||
            !RegExp(
              r'^assets/audio/backing_[a-z_]+(?:_(?:40|50|60|70|80)\.ogg|\.wav)$',
            ).hasMatch(backing['path']) ||
            backing['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(backing['sha256']) ||
            backing['base_tempo_bpm'] != 60 ||
            backing['total_ticks'] != start ||
            backing['duration_ms'] != (start * 1000 / ticksPerBeat).round())) {
      throw const FormatException('Invalid piece accompaniment');
    }
    if (backing is Map && backing['variants'] != null) {
      final variants = backing['variants'];
      if (variants is! Map || variants.length != 5) {
        throw const FormatException('Invalid accompaniment variants');
      }
      for (final tempo in [40, 50, 60, 70, 80]) {
        final variant = variants['$tempo'];
        if (variant is! Map ||
            variant['tempo_bpm'] != tempo ||
            variant['path'] is! String ||
            !RegExp('^assets/audio/backing_[a-z_]+_$tempo\\.ogg\$')
                .hasMatch(variant['path']) ||
            variant['sha256'] is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(variant['sha256']) ||
            variant['duration_ms'] !=
                (start * 60000 / (tempo * ticksPerBeat)).round() ||
            variant['sample_frames'] !=
                (start * 60 * 22050 / (tempo * ticksPerBeat)).round()) {
          throw const FormatException('Invalid accompaniment tempo');
        }
      }
    }
  }
  final Json data;
  Json? get accompaniment => data['accompaniment'] == null
      ? null
      : Map<String, dynamic>.from(data['accompaniment'] as Map);
  Json? accompanimentFor(int tempo) {
    final backing = accompaniment;
    if (backing == null) return null;
    final variants = backing['variants'];
    return variants is Map
        ? Map<String, dynamic>.from(variants['$tempo'] as Map)
        : backing;
  }

  late final List<PieceNote> notes;
  String get id => data['content_id'] as String;
  String title(String locale) => data['localized_title'][locale] as String;
  String description(String locale) =>
      data['localized_description'][locale] as String;
  String composer(String locale) => description(locale).split(' · ').first;
  int get tempo => data['tempo_bpm'] as int;
  int get ticksPerBeat => data['ticks_per_beat'] as int;
  int get ticks => notes.last.endTick;
  int get beatsPerBar => data['beats_per_bar'] as int;
  int get barTicks => beatsPerBar * ticksPerBeat;
  int get pickupTicks => data['pickup_ticks'] as int? ?? 0;
  int get bars => ((ticks - pickupTicks) / barTicks).ceil();
  int get keyCount => (data['key_steps'] as List?)?.length ?? 5;
  int keyStep(int key) => (data['key_steps'] as List?)?[key] as int? ?? key;
  // Supplementary marks follow the scale degree, including in other octaves.
  int keyShape(int key) => keyStep(key) % 7;
  String keyLabel(int key) {
    final step = keyStep(key);
    const white = [0, 2, 4, 5, 7, 9, 11];
    final natural =
        60 +
        (step ~/ 7 - (step < 0 && step % 7 != 0 ? 1 : 0)) * 12 +
        white[step % 7];
    final alteration = keyMidi(key) - natural;
    final octave = (step / 7).floor();
    final dots = List.filled(
      octave.abs(),
      octave < 0 ? '\u0323' : '\u0307',
    ).join();
    return '${alteration < 0
        ? '♭'
        : alteration > 0
        ? '♯'
        : ''}${step % 7 + 1}$dots';
  }

  int keyMidi(int key) {
    final explicit = data['key_midis'] as List?;
    if (explicit != null) return explicit[key] as int;
    final step = keyStep(key);
    const white = [0, 2, 4, 5, 7, 9, 11];
    return 60 + (step / 7).floor() * 12 + white[step % 7];
  }

  List<String> get keyLabels => [
    for (var i = 0; i < keyCount; i++) keyLabel(i),
  ];
  int get noteCount => notes.where((n) => !n.isRest).length;
  int soundingIndex(int index) =>
      notes.take(index).where((n) => !n.isRest).length;
  ({int sample, int rate}) playback(int key) {
    const samples = [60, 62, 64, 65, 67, 69, 71];
    final target = keyMidi(key);
    var closest = 0;
    for (var i = 1; i < samples.length; i++) {
      if ((target - samples[i]).abs() < (target - samples[closest]).abs()) {
        closest = i;
      }
    }
    return (
      sample: closest,
      rate: (math.pow(2, (target - samples[closest]) / 12) * 1000).round(),
    );
  }
}

enum PieceMode { ready, demo, playing, paused, complete }

/// Musical duration belongs to the score; no clinical training task or score
/// is created. A quarter beat is two integer ticks, including at changed tempi.
class PiecePlayer {
  PiecePlayer(this.piece, this.clock) : tempo = piece.tempo;
  final PianoPiece piece;
  final Clock clock;
  PieceMode mode = PieceMode.ready, _pausedMode = PieceMode.ready;
  int tempo, index = 0;
  int? pointer, _heldAt, _demoAnchor;
  int _demoElapsed = 0;
  bool tooShort = false, wrongKey = false;
  PieceNote get note => piece.notes[index.clamp(0, piece.notes.length - 1)];
  int atTick(int ticks) => ticks * 60000000 ~/ (tempo * piece.ticksPerBeat);
  int get durationUs => atTick(note.endTick) - atTick(note.startTick);
  bool get running => mode == PieceMode.demo || mode == PieceMode.playing;
  double get progress =>
      mode == PieceMode.demo ||
          mode == PieceMode.paused && _pausedMode == PieceMode.demo
      ? ((_demoElapsed - atTick(note.startTick)) / durationUs).clamp(0.0, 1.0)
      : _heldAt == null
      ? 0
      : ((clock.now - _heldAt!) / durationUs).clamp(0.0, 1.0);
  void setTempo(int value) {
    if (running ||
        mode == PieceMode.paused ||
        ![40, 50, 60, 70, 80].contains(value)) {
      throw StateError('Cannot change tempo');
    }
    tempo = value;
  }

  void start({required bool demo}) {
    index = 0;
    pointer = _heldAt = null;
    tooShort = wrongKey = false;
    _demoElapsed = 0;
    _demoAnchor = clock.now;
    mode = demo ? PieceMode.demo : PieceMode.playing;
  }

  void stop() {
    mode = PieceMode.ready;
    index = 0;
    pointer = _heldAt = null;
    tooShort = wrongKey = false;
    _demoElapsed = 0;
  }

  void tick() {
    if (mode != PieceMode.demo) return;
    _demoElapsed = clock.now - _demoAnchor!;
    if (_demoElapsed >= atTick(piece.ticks)) {
      mode = PieceMode.ready;
      index = 0;
      return;
    }
    while (index + 1 < piece.notes.length &&
        _demoElapsed >= atTick(note.endTick)) {
      index++;
    }
  }

  bool down(int id, int? key) {
    if (mode != PieceMode.playing || pointer != null) return false;
    wrongKey = key != note.key;
    if (wrongKey) return false;
    tooShort = false;
    pointer = id;
    _heldAt = clock.now;
    return true;
  }

  void up(int id, {bool cancel = false}) {
    if (pointer != id) return;
    final held = clock.now - _heldAt!;
    pointer = _heldAt = null;
    if (cancel) return;
    tooShort = held < durationUs;
    if (!tooShort && ++index == piece.notes.length) mode = PieceMode.complete;
  }

  void pause() {
    if (!running) return;
    if (mode == PieceMode.demo) {
      tick();
      if (!running) return;
    }
    _pausedMode = mode;
    pointer = _heldAt = null;
    mode = PieceMode.paused;
  }

  void resume() {
    if (mode != PieceMode.paused) return;
    mode = _pausedMode;
    if (mode == PieceMode.demo) _demoAnchor = clock.now - _demoElapsed;
  }
}
