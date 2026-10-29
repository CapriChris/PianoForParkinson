import 'package:flutter/material.dart';

import '../ui/qin_theme.dart';

/// Kept outside the keyboard hit rectangle. It describes the intended note
/// length; scoring and advancing belong to the task engine.
class KeyDurationGuide extends StatelessWidget {
  const KeyDurationGuide({
    super.key,
    required this.count,
    required this.targetKey,
    required this.progress,
    required this.durationMs,
    this.paused = false,
    this.tooShort = false,
    this.compact = false,
  });
  final int count, durationMs;
  final int? targetKey;
  final double progress;
  final bool paused, tooShort, compact;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SizedBox(
      height: compact ? 16 : 24,
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: i != targetKey
                  ? const SizedBox.shrink()
                  : Semantics(
                      label: zh
                          ? '${i + 1} 号键 · 按住琴键，条满后松开'
                          : 'Key ${i + 1} · Hold the key until the bar fills',
                      value: paused
                          ? (zh ? '已暂停' : 'Paused')
                          : '${(progress * 100).round()}%',
                      child: ExcludeSemantics(
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: tooShort
                                  ? context.qin.warning
                                  : context.qin.primary,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 12,
                              color: paused
                                  ? context.qin.muted
                                  : tooShort
                                  ? context.qin.warning
                                  : context.qin.primary,
                              backgroundColor: context.qin.soft,
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
  }
}
