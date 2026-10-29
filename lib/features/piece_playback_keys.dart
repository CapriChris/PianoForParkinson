import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/piano_piece.dart';
import '../ui/note_label.dart';
import '../ui/note_colors.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import 'key_press_feedback.dart';

/// Read-only keys share the same press and particle feedback as training.
class PiecePlaybackKeys extends StatelessWidget {
  const PiecePlaybackKeys({
    super.key,
    required this.piece,
    required this.active,
  });
  final PianoPiece piece;

  /// The value identifies a strike, including repeated strikes on one key.
  final Map<int, Object> active;

  @override
  Widget build(BuildContext context) => MusicTextScale(
    child: LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 3.0;
        final available = constraints.maxWidth;
        final width = math.min(
          40.0,
          math.max(
            30.0,
            (available - spacing * (piece.keyCount - 1)) / piece.keyCount,
          ),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var key = 0; key < piece.keyCount; key++) ...[
                if (key > 0) const SizedBox(width: spacing),
                KeyPressFeedback(
                  key: ValueKey('playback-feedback-$key'),
                  pressed: active.containsKey(key),
                  pulse: active[key],
                  color: NoteColors.degree(piece.keyStep(key)).fill,
                  child: Container(
                    width: width,
                    height: 46,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: active.containsKey(key)
                          ? NoteColors.degree(piece.keyStep(key)).pressed
                          : context.qin.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: context.qin.highContrast
                            ? context.qin.ink
                            : NoteColors.degree(piece.keyStep(key)).fill,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: FittedBox(
                        child: NoteLabel(
                          piece.keyLabel(key),
                          style:
                              (Theme.of(context).textTheme.bodySmall ??
                                      const TextStyle(fontSize: 16))
                                  .copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.qin.ink,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
