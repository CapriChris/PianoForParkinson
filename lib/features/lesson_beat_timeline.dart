import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/qin_theme.dart';
import 'metronome_pendulum.dart';

class LessonBeatTimeline extends StatelessWidget {
  const LessonBeatTimeline({
    super.key,
    required this.page,
    required this.elapsedMs,
    required this.running,
    required this.chinese,
    this.compact = false,
  });
  final int page, elapsedMs;
  final bool running, chinese, compact;
  double get progress => (elapsedMs / 6000).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final current = running ? (elapsedMs ~/ 1500).clamp(0, 3) : -1;
    final p = context.qin;
    String label(int i) => page == 0
        ? (chinese ? '拍点' : 'Beat')
        : page == 1 || i.isEven
        ? (chinese ? '弹奏' : 'Play')
        : (chinese ? '等待' : 'Wait');
    return Container(
      padding: EdgeInsets.all(compact ? 4 : 16),
      decoration: BoxDecoration(
        color: p.soft,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: MetronomePendulum(
                      running && !MediaQuery.disableAnimationsOf(context)
                          ? math.sin(elapsedMs / 1500 * math.pi)
                          : 0,
                      p.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  chinese ? '节拍器 · 40 拍/分' : 'Metronome · 40 BPM',
                  style: TextStyle(fontSize: 18, color: p.muted),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    selected: current == i,
                    label: '${i + 1} ${label(i)}',
                    child: ExcludeSemantics(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: compact ? 3 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: current == i ? p.primary : p.surface,
                          border: Border.all(
                            color: current == i ? p.primary : p.edge,
                            width: p.highContrast ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${i + 1} ${label(i)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.2,
                            fontWeight: current == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: current == i ? p.onPrimary : p.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: compact ? 2 : 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            semanticsLabel: chinese ? '整段示范进度' : 'Whole example progress',
          ),
        ],
      ),
    );
  }
}
