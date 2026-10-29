import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/scrolling_piece.dart';
import '../ui/note_label.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/note_colors.dart';
import 'key_press_feedback.dart';
import 'scrolling_score.dart';

/// Read-only demonstration. Sound, note bars and keys share the same timeline.
class PieceAuditionPreview extends StatelessWidget {
  const PieceAuditionPreview({
    super.key,
    required this.player,
    required this.frames,
    required this.chinese,
  });
  final ScrollingPiecePlayer player;
  final Listenable frames;
  final bool chinese;

  @override
  Widget build(BuildContext context) {
    final playing =
        player.mode == ScrollPieceMode.running &&
        !player.leadingIn &&
        player.targetKey != null;
    final scale = musicTextScalerOf(context);
    final palette = context.qin;
    return MusicTextScale(
      child: Semantics(
        label: chinese ? '试听演奏预览' : 'Performance preview',
        child: Container(
          key: const ValueKey('piece-visual-preview'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 156,
                child: ScrollingScore(
                  player: player,
                  frames: frames,
                  chinese: chinese,
                  demonstrating: playing,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: math.max(76, scale.scale(24) + 44),
                child: Row(
                  children: [
                    for (var key = 0; key < player.piece.keyCount; key++) ...[
                      if (key > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Semantics(
                          label: chinese
                              ? '预览琴键 ${player.piece.keyLabel(key)}'
                              : 'Preview key ${player.piece.keyLabel(key)}',
                          selected: playing && player.targetKey == key,
                          child: KeyPressFeedback(
                            key: ValueKey('preview-feedback-$key'),
                            pressed: playing && player.targetKey == key,
                            enabled: player.mode == ScrollPieceMode.running,
                            pulse: playing && player.targetKey == key
                                ? (player, player.currentIndex)
                                : null,
                            color: NoteColors.degree(player.piece.keyStep(key))
                                .fill,
                            child: Container(
                              key: ValueKey('preview-key-$key'),
                              decoration: BoxDecoration(
                                color: playing && player.targetKey == key
                                    ? NoteColors.degree(
                                        player.piece.keyStep(key),
                                      ).pressed
                                    : palette.soft,
                                border: Border.all(
                                  color: palette.highContrast
                                      ? palette.ink
                                      : NoteColors.degree(
                                          player.piece.keyStep(key),
                                        ).fill,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: NoteLabel(
                                        player.piece.keyLabel(key),
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w700,
                                          color:
                                              playing && player.targetKey == key
                                              ? palette.highContrast
                                                    ? palette.ink
                                                    : NoteColors.degree(
                                                        player.piece.keyStep(
                                                          key,
                                                        ),
                                                      ).ink
                                              : palette.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
