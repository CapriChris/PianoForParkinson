import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_controller.dart';
import '../domain/piano_piece.dart';
import '../domain/piece_trace.dart';
import '../ui/qin_components.dart';
import '../ui/qin_theme.dart';
import 'piece_playback_keys.dart';
import 'piece_replay_audio.dart';
import 'piece_continuous_score.dart';

/// A scrollable score with one native audio timeline for audition and seeking.
class PieceSheetPreview extends StatefulWidget {
  const PieceSheetPreview({
    super.key,
    required this.c,
    required this.piece,
    required this.tempo,
  });
  final AppController c;
  final PianoPiece piece;
  final int tempo;
  @override
  State<PieceSheetPreview> createState() => PieceSheetPreviewState();
}

class PieceSheetPreviewState extends State<PieceSheetPreview>
    with SingleTickerProviderStateMixin {
  late final audio = PieceReplayAudio(widget.c, widget.piece);
  late final Ticker ticker;
  final position = ValueNotifier<int>(0), selection = ValueNotifier<int>(-1);
  late final ValueNotifier<int> timeline;
  final scroll = ScrollController();
  int epoch = 0, anchor = 0, lastPoll = 0, pulse = 0, previewEnd = 0;
  int? previewKey;
  int pausedLead = 0;
  bool playing = false, preparing = false, prepared = false, polling = false;
  bool solo = false, needsLead = true, scrubResume = false;
  bool draggingScore = false, resumeAfterDrag = false;
  Future<void>? scrubPause;
  Future<void>? dragPause;
  String? error;
  int get duration =>
      widget.piece.ticks *
      60000000 ~/
      (widget.tempo * widget.piece.ticksPerBeat);
  PieceReviewData get data => PieceReviewData({
    'tempo_bpm': widget.tempo,
    'duration_us': duration,
    'matched_notes': <int>[],
  }, widget.piece);
  int get lead => 4 * 60000000 ~/ widget.tempo;

  void alignScore(int at) {
    if (!scroll.hasClients || draggingScore) return;
    final offset = ContinuousScoreLayout.offsetAt(
      at,
      widget.tempo,
    ).clamp(0.0, scroll.position.maxScrollExtent);
    if ((scroll.offset - offset).abs() > .01) scroll.jumpTo(offset);
  }

  void updateFromScore(double offset) {
    final at = ContinuousScoreLayout.timeAt(
      offset,
      widget.tempo,
    ).clamp(-lead, duration);
    timeline.value = at;
    position.value = at.clamp(0, duration);
    pausedLead = math.min(0, at);
    needsLead = false;
    selection.value = -1;
  }

  bool onScoreNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      draggingScore = true;
      resumeAfterDrag = playing;
      dragPause = pause();
    } else if (notification is ScrollUpdateNotification && draggingScore) {
      updateFromScore(notification.metrics.pixels);
    } else if (notification is ScrollEndNotification && draggingScore) {
      updateFromScore(notification.metrics.pixels);
      draggingScore = false;
      final resume = resumeAfterDrag, token = epoch, pending = dragPause;
      if (resume) {
        unawaited(() async {
          await pending;
          if (mounted && token == epoch && !draggingScore) await play();
        }());
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    timeline = ValueNotifier<int>(-lead);
    ticker = createTicker((_) => frame());
    widget.c.previewInterruptions.addListener(interrupted);
  }

  @override
  void didUpdateWidget(covariant PieceSheetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tempo != widget.tempo || oldWidget.piece != widget.piece) {
      interrupted();
      position.value = 0;
      selection.value = -1;
      needsLead = true;
      pausedLead = 0;
      timeline.value = -lead;
      if (scroll.hasClients) scroll.jumpTo(0);
    }
  }

  void interrupted() {
    ++epoch;
    ticker.stop();
    playing = preparing = prepared = solo = false;
    previewKey = null;
    pausedLead = 0;
    unawaited(audio.stop().catchError((_) {}));
    if (mounted) setState(() {});
  }

  Future<void> stop() async {
    ++epoch;
    ticker.stop();
    playing = preparing = prepared = solo = false;
    previewKey = null;
    pausedLead = 0;
    await audio.stop();
    if (mounted) setState(() {});
  }

  Future<void> pause() async {
    if (playing) {
      pausedLead = math.min(0, widget.c.clock.now - anchor);
      timeline.value = widget.c.clock.now - anchor;
    }
    ++epoch;
    ticker.stop();
    playing = preparing = false;
    if (solo) {
      solo = false;
      prepared = false;
      previewKey = null;
      await audio.stop();
    } else {
      await audio.pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> play() async {
    if (preparing) return;
    if (playing) return pause();
    final token = ++epoch;
    solo = false;
    previewKey = null;
    ticker.stop();
    setState(() {
      preparing = true;
      error = null;
    });
    try {
      if (position.value >= duration) {
        position.value = 0;
        needsLead = true;
      }
      if (!prepared) {
        final d = data;
        await audio.prepare(
          notes: d.demoNotes(),
          durationUs: duration,
          tempo: widget.tempo,
          segments: d.segments(false),
          backing: true,
        );
        if (!mounted || token != epoch) return;
        prepared = true;
      }
      final start = pausedLead < 0
          ? pausedLead
          : needsLead && position.value == 0
          ? -lead
          : position.value;
      pausedLead = 0;
      needsLead = false;
      await audio.play(start);
      if (!mounted || token != epoch) return;
      timeline.value = start;
      anchor = widget.c.clock.now - start;
      lastPoll = 0;
      alignScore(start);
      playing = true;
      ticker.start();
    } catch (_) {
      if (mounted && token == epoch) {
        prepared = false;
        error = widget.c.text(
          '试听暂不可用，请重试',
          'Preview unavailable. Please retry',
        );
      }
    } finally {
      if (mounted && token == epoch) setState(() => preparing = false);
    }
  }

  Future<void> tapNote(int index) async {
    final n = widget.piece.notes[index], d = data, token = ++epoch;
    ticker.stop();
    playing = preparing = prepared = solo = false;
    previewKey = null;
    needsLead = false;
    pausedLead = 0;
    selection.value = index;
    position.value = d.tickUs(n.startTick);
    timeline.value = position.value;
    alignScore(position.value);
    setState(() => error = null);
    if (n.isRest) {
      await audio.stop();
      return;
    }
    final length = d.tickUs(n.endTick) - d.tickUs(n.startTick);
    try {
      await audio.prepare(
        notes: [
          {'key': n.key, 'start_us': 0, 'duration_us': length},
        ],
        durationUs: length + 280000,
        tempo: widget.tempo,
        segments: [],
        backing: false,
      );
      if (!mounted || token != epoch) return;
      await audio.play(0);
      if (!mounted || token != epoch) return;
      solo = true;
      previewKey = n.key;
      pulse++;
      previewEnd = widget.c.clock.now + length + 280000;
      ticker.start();
      setState(() {});
    } catch (_) {
      if (mounted && token == epoch) {
        setState(
          () => error = widget.c.text('琴音暂不可用', 'Piano sound unavailable'),
        );
      }
    }
  }

  void frame() {
    if (solo) {
      if (widget.c.clock.now >= previewEnd) {
        solo = false;
        previewKey = null;
        ticker.stop();
        unawaited(audio.stop().catchError((_) {}));
        if (mounted) setState(() {});
      }
      return;
    }
    if (!playing) return;
    final elapsed = widget.c.clock.now - anchor;
    timeline.value = elapsed.clamp(-lead, duration);
    position.value = elapsed.clamp(0, duration);
    alignScore(timeline.value);
    if (position.value >= duration) {
      playing = false;
      ticker.stop();
      unawaited(audio.pause().catchError((_) {}));
      setState(() {});
      return;
    }
    if (!polling && widget.c.clock.now - lastPoll >= 80000) {
      polling = true;
      lastPoll = widget.c.clock.now;
      final token = epoch, sent = widget.c.clock.now;
      unawaited(
        audio
            .position()
            .then((p) {
              if (mounted && token == epoch && playing && p != null) {
                anchor =
                    widget.c.clock.now - p - (widget.c.clock.now - sent) ~/ 2;
              }
            })
            .catchError((Object _) {
              if (mounted && token == epoch) {
                interrupted();
                setState(
                  () => error = widget.c.text(
                    '试听已中断，请重试',
                    'Preview interrupted. Please retry',
                  ),
                );
              }
            })
            .whenComplete(() => polling = false),
      );
    }
  }

  String time(int us) {
    final seconds = us ~/ 1000000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    ++epoch;
    widget.c.previewInterruptions.removeListener(interrupted);
    ticker.dispose();
    audio.close();
    position.dispose();
    timeline.dispose();
    selection.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = data, piece = widget.piece;
    return QinPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: ContinuousScoreLayout(piece, constraints.maxWidth).height,
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: onScoreNotification,
                    child: SingleChildScrollView(
                      key: const ValueKey('audition-score-scroll'),
                      controller: scroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: ContinuousScoreLayout(
                          piece,
                          constraints.maxWidth,
                        ).width,
                        child: PieceContinuousScore(
                          data: d,
                          selection: selection,
                          onNote: tapNote,
                          chinese: widget.c.chinese,
                          viewportWidth: constraints.maxWidth,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: FixedScoreGuide(
                      piece: piece,
                      tempo: widget.tempo,
                      timeline: timeline,
                      counting: playing || pausedLead < 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: position,
            builder: (context, pos, _) {
              final active = <int, Object>{};
              if (solo && previewKey != null) {
                active[previewKey!] = ('preview', pulse);
              }
              if (playing) {
                for (final n in d.demoNotes()) {
                  if (pos >= n['start_us'] &&
                      pos < n['start_us'] + n['duration_us'] &&
                      widget.c.clock.now >= anchor) {
                    active[n['key'] as int] = ('note', n['start_us']);
                  }
                }
              }
              return PiecePlaybackKeys(piece: piece, active: active);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: ValueListenableBuilder<int>(
              valueListenable: position,
              builder: (context, pos, _) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(time(pos)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      alignment: Alignment.centerRight,
                      fit: BoxFit.scaleDown,
                      child: Text(time(duration)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                key: const ValueKey('piece-audition'),
                tooltip: widget.c.text(
                  playing ? '暂停试听' : '播放试听',
                  playing ? 'Pause preview' : 'Play preview',
                ),
                onPressed: preparing ? null : play,
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: Colors.transparent,
                ),
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.qin.highContrast
                        ? context.qin.primary
                        : context.qin.soft,
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: context.qin.highContrast
                        ? context.qin.onPrimary
                        : context.qin.primary,
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: position,
                  builder: (context, pos, _) => Slider(
                    key: const ValueKey('audition-seek'),
                    value: pos.clamp(0, duration).toDouble(),
                    max: math.max(1, duration).toDouble(),
                    onChangeStart: (_) {
                      scrubResume = playing;
                      scrubPause = pause();
                    },
                    onChanged: (v) {
                      needsLead = false;
                      pausedLead = 0;
                      position.value = v.round();
                      timeline.value = position.value;
                      alignScore(position.value);
                    },
                    onChangeEnd: (_) async {
                      await scrubPause;
                      if (scrubResume && mounted) await play();
                    },
                  ),
                ),
              ),
            ],
          ),
          if (error != null) QinStatus(text: error!, tone: QinTone.error),
        ],
      ),
    );
  }
}
