import 'piano_piece.dart';

enum PiecePracticeMode { continuous, beginner }

/// Versioned training rules. A beat-based gap keeps repeated notes visibly apart
/// at every tempo while preserving the original score's onset times.
class PieceTiming {
  static const version = 2;
  static const onsetToleranceUs = 150000;
  static const releaseToleranceUs = 120000;
  static const gapBeats = .125;
  static const pixelsPerBeat = 72.0;

  /// Dragging sticks near multiples of ten; +/- buttons remain one BPM steps.
  static int snapTempo(double value, int originalTempo) {
    final bounded = value.clamp(30.0, originalTempo.toDouble());
    final anchor = (bounded / 10).round() * 10;
    return anchor >= 30 &&
            anchor <= originalTempo &&
            (bounded - anchor).abs() <= 2
        ? anchor
        : bounded.round();
  }

  static int gapUs(int tempo) => (60000000 * gapBeats / tempo).round();

  static int endUs(PianoPiece piece, int index, int tempo) =>
      piece.notes[index].endTick * 60000000 ~/ (tempo * piece.ticksPerBeat) -
      gapUs(tempo);
}
