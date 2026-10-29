import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/task_engine.dart';
import '../ui/qin_theme.dart';
import 'metronome_pendulum.dart';

class RhythmTimeline extends StatelessWidget {
  const RhythmTimeline({super.key, required this.task, required this.chinese});
  final TaskEngine task;
  final bool chinese;
  @override
  Widget build(BuildContext context) {
    final beat = task.leadInBeat;
    final phase = task.phase == 'paused' ? 'paused' : task.phase;
    final active = {
      'cue',
      'beatPrepare',
      'response',
      'holdTail',
      'phraseEnd',
    }.contains(phase);
    final current = task.responsiveControls
        ? task.soundingNoteIndex
        : task.trialIndex;
    final pulse = task.responsiveControls && task.rhythmPulse != null
        ? task.rhythmPulse!
        : active
        ? task.trialIndex - task.beatRemainingUs / task.beatIntervalUs
        : beat != null
        ? task.leadInProgress
        : 0.0;
    final soundingBeat = pulse >= 0 ? pulse.floor() % 4 : 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.qin.soft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.qin.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                height: 32,
                child: CustomPaint(
                  painter: MetronomePendulum(
                    !MediaQuery.disableAnimationsOf(context) &&
                            (active || beat != null || phase == 'demo')
                        ? math.sin(pulse * math.pi)
                        : 0,
                    context.qin.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  beat != null
                      ? (chinese
                            ? '${task.preparingDemo ? '演示 · ' : '轮到你了 · '}预备拍 $beat / 4'
                            : '${task.preparingDemo ? 'Demo count in' : 'Count in'} $beat / 4')
                      : (chinese
                            ? (active
                                  ? '${current == null ? '' : '${task.song[current] + 1} 号键 · '}${task.bpm} 拍/分'
                                  : '先看，先听 · ${task.bpm} 拍/分')
                            : (active
                                  ? '${current == null ? '' : 'Key ${task.song[current] + 1} · '}${task.bpm} BPM'
                                  : 'Watch and listen · ${task.bpm} BPM')),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    width: 22 * MediaQuery.textScalerOf(context).scale(1),
                    height: 22 * MediaQuery.textScalerOf(context).scale(1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          (beat != null
                              ? i == beat - 1
                              : (active || phase == 'demo') &&
                                    i == soundingBeat)
                          ? context.qin.primary
                          : Colors.transparent,
                      border: Border.all(color: context.qin.edge),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              (beat != null
                                  ? i == beat - 1
                                  : (active || phase == 'demo') &&
                                        i == soundingBeat)
                              ? context.qin.onPrimary
                              : context.qin.muted,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < task.song.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: (active || phase == 'demo') && i == current
                          ? context.qin.primary
                          : context.qin.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current != null && i < current
                            ? context.qin.edge
                            : context.qin.edge,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${task.song[i] + 1}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: (active || phase == 'demo') && i == current
                              ? context.qin.onPrimary
                              : context.qin.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: task.phraseProgress,
              minHeight: 4,
              semanticsLabel: chinese ? '整组演奏进度' : 'Whole phrase progress',
              color: context.qin.primary,
              backgroundColor: context.qin.disabled,
            ),
          ),
        ],
      ),
    );
  }
}
