import 'package:flutter/material.dart';

/// Distinct colors follow the diatonic degree, independently of register or key
/// position. Accidentals keep the color of their written degree.
@immutable
class NoteTone {
  const NoteTone(this.fill, this.ink);
  final Color fill, ink;
  Color get pressed => Color.lerp(fill, ink, .10)!;
}

abstract final class NoteColors {
  static const tones = [
    NoteTone(Color(0xffee786a), Color(0xff361713)), // coral
    NoteTone(Color(0xfff0af42), Color(0xff563500)), // amber
    NoteTone(Color(0xffd9cd36), Color(0xff454000)), // gold
    NoteTone(Color(0xff73be5a), Color(0xff173410)), // green
    NoteTone(Color(0xff26bba4), Color(0xff04342b)), // turquoise
    NoteTone(Color(0xff63a3ed), Color(0xff102d52)), // blue
    NoteTone(Color(0xffb58ae4), Color(0xff351944)), // purple
  ];
  static NoteTone degree(int zeroBasedDegree) => tones[zeroBasedDegree % 7];
}
