import 'package:flutter/material.dart';

enum PracticeHand {
  left,
  right;

  Color get color =>
      this == left ? const Color(0xFF1D4ED8) : const Color(0xFFC2410C);
  String label(bool chinese) => this == left
      ? (chinese ? '左手' : 'Left hand')
      : (chinese ? '右手' : 'Right hand');
}

/// Only tasks that require an actual hand receive hand labels. Cognitive
/// position/shape keys and melody pitch keys do not imply a required hand.
PracticeHand? handForKey(String? taskId, int key) => switch (taskId) {
  'M1_ALTERNATE' =>
    key == 0
        ? PracticeHand.left
        : key == 1
        ? PracticeHand.right
        : null,
  'M2_DUAL_ZONE' =>
    key >= 0 && key < 6
        ? (key < 3 ? PracticeHand.left : PracticeHand.right)
        : null,
  _ => null,
};

class HandCue extends StatelessWidget {
  const HandCue({
    super.key,
    required this.hand,
    required this.chinese,
    required this.keyNumber,
  });
  final PracticeHand hand;
  final bool chinese;
  final int keyNumber;
  @override
  Widget build(BuildContext context) => Text(
    '${hand.label(chinese)} · ${chinese ? '$keyNumber 号键' : 'Key $keyNumber'}',
    key: ValueKey('hand-cue-${hand.name}'),
    textAlign: TextAlign.center,
    style: TextStyle(
      color: hand.color,
      fontSize: 22,
      fontWeight: FontWeight.w700,
    ),
  );
}
