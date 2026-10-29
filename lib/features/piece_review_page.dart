import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/app_controller.dart';
import '../app/page_title.dart';
import '../domain/contracts.dart';
import '../domain/piano_piece.dart';
import '../domain/piece_trace.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import '../ui/metric_visuals.dart';
import 'piece_replay_audio.dart';
import 'piece_review_score.dart';
import 'piece_playback_keys.dart';

PianoPiece? reviewScore(AppController c, Json record) {
  try {
    if (record['score_snapshot'] is Map) {
      return PianoPiece.fromJson(
        Map<String, dynamic>.from(record['score_snapshot'] as Map),
      );
    }
    final current = c.content.pieceFor(record['content_id'] as String);
    return current?.data['content_hash'] == record['content_hash']
        ? current
        : null;
  } catch (_) {
    return null;
  }
}

class PieceReviewCard extends StatefulWidget {
  const PieceReviewCard({
    super.key,
    required this.c,
    required this.record,
    this.compact = false,
    this.backgroundOpacity = 1,
  });
  final AppController c;
  final Json record;
  final bool compact;
  final double backgroundOpacity;
  @override
  State<PieceReviewCard> createState() => _PieceReviewCardState();
}

class _PieceReviewCardState extends State<PieceReviewCard> {
  final playhead = ValueNotifier<int>(-1), selection = ValueNotifier<int>(-1);
  @override
  void dispose() {
    playhead.dispose();
    selection.dispose();
    super.dispose();
  }

  void open([int? note]) {
    final piece = reviewScore(widget.c, widget.record);
    if (piece == null) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PieceReviewPage(
          c: widget.c,
          record: widget.record,
          piece: piece,
          initialNote: note,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, piece = reviewScore(c, widget.record);
    if (widget.compact) {
      final contrast = context.qin.highContrast;
      final available = piece != null;
      final background = contrast || !available
          ? context.qin.surface
          : context.qin.primary;
      final foreground = contrast || !available
          ? context.qin.ink
          : Colors.white;
      return Material(
        color: background.withValues(
          alpha: contrast ? 1 : widget.backgroundOpacity,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: contrast || !available ? context.qin.line : background,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('open-piece-review'),
          onTap: available ? open : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: foreground.withValues(alpha: contrast ? .08 : .15),
                  ),
                  child: Icon(Icons.graphic_eq, color: foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.text('逐音回顾', 'Performance review'),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(color: foreground),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        available
                            ? c.text(
                                '查看每个音符的演奏情况',
                                'Review your performance note by note',
                              )
                            : c.text(
                                '旧记录未保存原谱，无法还原完整乐谱',
                                'The original score was not saved with this older record',
                              ),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
                if (available) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: foreground),
                    ),
                    child: Icon(Icons.chevron_right, color: foreground),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      key: const ValueKey('open-piece-review'),
      onTap: piece == null ? null : open,
      borderRadius: BorderRadius.circular(18),
      child: QinPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.text('逐音回顾', 'Performance review'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (piece != null) const Icon(Icons.chevron_right),
              ],
            ),
            if (piece != null) ...[
              IgnorePointer(
                child: ReviewStaff(
                  data: PieceReviewData(widget.record, piece),
                  measure: 0,
                  playhead: playhead,
                  selection: selection,
                  onNote: open,
                  userMode: true,
                  preservePauses: false,
                  chinese: c.chinese,
                  showMeasureLabel: false,
                ),
              ),
            ] else ...[
              MetricNoteMap(
                total: widget.record['total_notes'] as int,
                matched: Set<int>.from(widget.record['matched_notes'] as List),
                chinese: c.chinese,
              ),
              MetricNote(
                c.text(
                  '旧记录未保存原谱，无法还原完整乐谱',
                  'The original score was not saved with this older record',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PieceReviewPage extends StatefulWidget {
  const PieceReviewPage({
    super.key,
    required this.c,
    required this.record,
    required this.piece,
    this.initialNote,
    this.initialTouch,
  });
  final AppController c;
  final Json record;
  final PianoPiece piece;
  final int? initialNote;
  final Json? initialTouch;
  @override
  State<PieceReviewPage> createState() => _PieceReviewPageState();
}

class _PieceReviewPageState extends State<PieceReviewPage>
    with SingleTickerProviderStateMixin {
  AppController get c => widget.c;
  late final data = PieceReviewData(widget.record, widget.piece);
  late final audio = PieceReplayAudio(c, widget.piece);
  late final Ticker ticker;
  late bool userMode = data.canReplay;
  late bool preservePauses = data.wallDuration <= 590000000;
  bool backing = true,
      follow = true,
      playing = false,
      busy = false,
      prepared = false,
      polling = false,
      scrubResume = false,
      preview = false;
  int epoch = 0, anchor = 0, lastPoll = 0, lastMeasure = -1, previewEnd = 0;
  String? error;
  int? previewKey;
  int previewPulse = 0;
  final playhead = ValueNotifier<int>(0), selection = ValueNotifier<int>(-1);
  late final measureKeys = List.generate(
    widget.piece.bars + (widget.piece.pickupTicks > 0 ? 1 : 0),
    (_) => GlobalKey(),
  );
  bool get backingAvailable {
    final now = c.content
        .pieceFor(widget.piece.id)
        ?.accompanimentFor(widget.record['tempo_bpm'] as int);
    return now != null &&
        now['sha256'] ==
            widget.piece.accompanimentFor(
              widget.record['tempo_bpm'] as int,
            )?['sha256'];
  }

  int get duration =>
      userMode && preservePauses ? data.wallDuration : data.scoreDuration;
  List<Json> get notes =>
      userMode ? data.replayNotes(preservePauses) : data.demoNotes();
  @override
  void initState() {
    super.initState();
    ticker = createTicker((_) => frame());
    c.previewInterruptions.addListener(interrupted);
    if (widget.initialTouch != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => tapRecorded(widget.initialTouch!),
      );
    } else if (widget.initialNote != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => tapNote(widget.initialNote!),
      );
    }
  }

  String time(int us) {
    final sec = us ~/ 1000000;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  void interrupted() {
    ++epoch;
    playing = busy = prepared = preview = false;
    previewKey = null;
    ticker.stop();
    unawaited(audio.stop().catchError((_) {}));
    if (mounted) setState(() {});
  }

  Future<void> pause() async {
    ++epoch;
    playing = false;
    previewKey = null;
    ticker.stop();
    if (preview) {
      preview = false;
      prepared = false;
      await audio.stop();
    } else {
      await audio.pause();
    }
    if (mounted) setState(() {});
  }

  Future<void> play() async {
    if (busy) return;
    if (playing) {
      await pause();
      return;
    }
    final token = ++epoch;
    preview = false;
    previewKey = null;
    ticker.stop();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (playhead.value >= duration) playhead.value = 0;
      if (!prepared || preview) {
        await audio.prepare(
          notes: notes,
          durationUs: duration,
          tempo: widget.record['tempo_bpm'] as int,
          segments: data.segments(userMode && preservePauses),
          backing: backing && backingAvailable,
          releaseCuts: userMode
              ? [
                  for (final p in data.pauses)
                    p[preservePauses ? 'start_us' : 'score_us'] as int,
                ]
              : const [],
        );
        if (!mounted || token != epoch) return;
        prepared = true;
        preview = false;
      }
      await audio.play(playhead.value);
      if (!mounted || token != epoch) return;
      anchor = c.clock.now - playhead.value;
      lastPoll = 0;
      playing = true;
      ticker.start();
    } catch (_) {
      if (mounted && token == epoch) {
        prepared = false;
        await audio.stop().catchError((_) {});
        error = c.text('回放暂不可用，请重试', 'Replay unavailable. Please retry');
      }
    } finally {
      if (mounted && token == epoch) setState(() => busy = false);
    }
  }

  Future<void> tapNote(int index) async {
    final note = widget.piece.notes[index];
    final token = ++epoch;
    playing = false;
    preview = false;
    previewKey = null;
    ticker.stop();
    prepared = false;
    selection.value = index;
    playhead.value = userMode && preservePauses
        ? data.wallAt(data.tickUs(note.startTick))
        : data.tickUs(note.startTick);
    if (note.isRest) {
      setState(() {
        busy = false;
        error = null;
      });
      await audio.stop();
      return;
    }
    setState(() {
      error = null;
      busy = false;
    });
    try {
      final length = data.tickUs(note.endTick) - data.tickUs(note.startTick);
      await audio.prepare(
        notes: [
          {'key': note.key, 'start_us': 0, 'duration_us': length},
        ],
        durationUs: length + 280000,
        tempo: widget.record['tempo_bpm'] as int,
        segments: [],
        backing: false,
      );
      if (!mounted || token != epoch) return;
      await audio.play(0);
      if (!mounted || token != epoch) return;
      preview = true;
      previewKey = note.key;
      previewPulse++;
      previewEnd = c.clock.now + length + 280000;
      ticker.start();
    } catch (_) {
      if (mounted && token == epoch) {
        error = c.text('琴音暂不可用', 'Piano sound unavailable');
      }
    } finally {
      if (mounted && token == epoch) setState(() {});
    }
  }

  Future<void> tapRecorded(Json n) async {
    final token = ++epoch;
    playing = false;
    preview = false;
    previewKey = null;
    ticker.stop();
    prepared = false;
    selection.value = -1;
    playhead.value =
        n[userMode && preservePauses ? 'wall_start_us' : 'start_us'] as int;
    final length = ((n['end_us'] as int) - (n['start_us'] as int)).clamp(
      80000,
      600000000,
    );
    setState(() {
      error = null;
      busy = false;
    });
    try {
      await audio.prepare(
        notes: [
          {'key': n['key'], 'start_us': 0, 'duration_us': length},
        ],
        durationUs: length + 280000,
        tempo: widget.record['tempo_bpm'] as int,
        segments: [],
        backing: false,
      );
      if (!mounted || token != epoch) return;
      await audio.play(0);
      if (!mounted || token != epoch) return;
      preview = true;
      previewKey = n['key'] as int;
      previewPulse++;
      previewEnd = c.clock.now + length + 280000;
      ticker.start();
    } catch (_) {
      if (mounted && token == epoch) {
        error = c.text('琴音暂不可用', 'Piano sound unavailable');
      }
    } finally {
      if (mounted && token == epoch) setState(() {});
    }
  }

  void frame() {
    if (preview) {
      if (c.clock.now >= previewEnd) {
        preview = false;
        previewKey = null;
        ticker.stop();
        unawaited(audio.pause().catchError((_) {}));
        if (mounted) setState(() {});
      }
      return;
    }
    if (!playing) return;
    playhead.value = (c.clock.now - anchor).clamp(0, duration);
    if (playhead.value >= duration) {
      playing = false;
      ticker.stop();
      unawaited(audio.pause().catchError((_) {}));
      setState(() {});
      return;
    }
    if (!polling && c.clock.now - lastPoll >= 80000) {
      polling = true;
      lastPoll = c.clock.now;
      final token = epoch, sent = c.clock.now;
      unawaited(
        audio
            .position()
            .then((position) {
              if (mounted && playing && token == epoch && position != null) {
                anchor = c.clock.now - position - (c.clock.now - sent) ~/ 2;
              }
            })
            .catchError((Object _) {
              if (mounted && token == epoch) {
                interrupted();
                setState(
                  () => error = c.text(
                    '回放已中断，点击继续',
                    'Replay interrupted. Tap to continue',
                  ),
                );
              }
            })
            .whenComplete(() => polling = false),
      );
    }
    if (follow) {
      final score = data.scoreAt(
        playhead.value,
        preservePauses: userMode && preservePauses,
      );
      final tick =
          score *
          (widget.record['tempo_bpm'] as int) *
          widget.piece.ticksPerBeat /
          60000000;
      final measure = widget.piece.pickupTicks > 0
          ? (tick < widget.piece.pickupTicks
                ? 0
                : 1 +
                      ((tick - widget.piece.pickupTicks) /
                              widget.piece.barTicks)
                          .floor())
          : (tick / widget.piece.barTicks).floor();
      if (measure != lastMeasure && measure < measureKeys.length) {
        lastMeasure = measure;
        final target = measureKeys[measure].currentContext;
        if (target != null) {
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignment: .08,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
            ),
          );
        }
      }
    }
  }

  Future<void> switchMode(bool user) async {
    interrupted();
    userMode = user;
    selection.value = -1;
    playhead.value = 0;
    lastMeasure = -1;
    if (mounted) setState(() {});
  }

  Future<void> optionHelp(String title, String description) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.text('知道了', 'Got it')),
        ),
      ],
    ),
  );

  Widget explainedOption({
    required String id,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Widget? subtitle,
  }) => Row(
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title),
                  IconButton(
                    key: ValueKey('review-$id-help'),
                    tooltip: c.text('$title：说明', '$title: help'),
                    onPressed: () => optionHelp(title, description),
                    icon: const Icon(Icons.help_outline),
                  ),
                ],
              ),
              ?subtitle,
            ],
          ),
        ),
      ),
      Switch(
        key: ValueKey('review-$id-switch'),
        value: value,
        onChanged: onChanged,
      ),
      const SizedBox(width: 16),
    ],
  );

  Future<void> options() async {
    await pause();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text(c.text('同步伴奏', 'Accompaniment')),
                subtitle: backingAvailable
                    ? null
                    : Text(
                        c.text(
                          '此记录的伴奏版本已更新，仅回放按键',
                          'Backing version changed; input-only replay',
                        ),
                      ),
                value: backing && backingAvailable,
                onChanged: !backingAvailable
                    ? null
                    : (v) {
                        setState(() => backing = v);
                        refresh(() {});
                        prepared = false;
                      },
              ),
              if (data.canReplay)
                explainedOption(
                  id: 'pauses',
                  title: c.text('回放包含练习时的暂停', 'Include practice pauses'),
                  description: c.text(
                    '开启：按原来的时长重现练习中的暂停。\n关闭：跳过暂停，连续回放。',
                    'On: replay the pauses from your practice at their original length.\nOff: skip those pauses for continuous playback.',
                  ),
                  subtitle: data.wallDuration > 590000000
                      ? Text(
                          c.text(
                            '暂停较长，回放将跳过暂停',
                            'Long pauses are skipped for replay',
                          ),
                        )
                      : null,
                  value: preservePauses,
                  onChanged: data.wallDuration > 590000000
                      ? null
                      : (v) {
                          setState(() => preservePauses = v);
                          refresh(() {});
                          prepared = false;
                          playhead.value = 0;
                        },
                ),
              explainedOption(
                id: 'follow',
                title: c.text('播放时自动滚动乐谱', 'Scroll score during playback'),
                description: c.text(
                  '开启：播放到下一小节时，自动将它滚动到可见区域。\n关闭：乐谱不自动滚动，可自行上下滑动查看。',
                  'On: scroll the current measure into view during playback.\nOff: scroll through the score yourself.',
                ),
                value: follow,
                onChanged: (v) {
                  setState(() => follow = v);
                  refresh(() {});
                  lastMeasure = -1;
                },
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(c.text('完成', 'Done')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget playbackKeys() => ValueListenableBuilder<int>(
    valueListenable: playhead,
    builder: (context, position, _) {
      final active = <int, Object>{};
      if (preview && previewKey != null) {
        active[previewKey!] = ('preview', previewPulse);
      }
      if (playing) {
        if (userMode) {
          for (final n in data.touches) {
            if (position >= n[preservePauses ? 'wall_start_us' : 'start_us'] &&
                position <
                    n[preservePauses ? 'touch_wall_end_us' : 'touch_end_us']) {
              active[n['key'] as int] = (
                'touch',
                n['wall_start_us'],
                n['start_us'],
              );
            }
          }
        } else {
          for (final n in data.demoNotes()) {
            if (position >= n['start_us'] &&
                position < n['start_us'] + n['duration_us']) {
              active[n['key'] as int] = ('note', n['start_us']);
            }
          }
        }
      }
      return PiecePlaybackKeys(piece: widget.piece, active: active);
    },
  );

  Widget playbackControls() => Column(
    children: [
      playbackKeys(),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(left: 60),
        child: ValueListenableBuilder<int>(
          valueListenable: playhead,
          builder: (context, position, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time(position),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time(duration),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          IconButton(
            key: const ValueKey('review-play'),
            tooltip: c.text(
              playing ? '暂停回放' : '播放回放',
              playing ? 'Pause replay' : 'Play replay',
            ),
            onPressed: busy ? null : play,
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
                    : context.qin.surface,
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
              valueListenable: playhead,
              builder: (context, position, _) => Slider(
                key: const ValueKey('review-seek'),
                value: position.clamp(0, duration).toDouble(),
                max: duration.toDouble(),
                onChangeStart: busy
                    ? null
                    : (_) {
                        scrubResume = playing;
                        unawaited(pause());
                      },
                onChanged: busy ? null : (v) => playhead.value = v.round(),
                onChangeEnd: busy
                    ? null
                    : (_) {
                        if (scrubResume) unawaited(play());
                      },
              ),
            ),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    ++epoch;
    c.previewInterruptions.removeListener(interrupted);
    ticker.dispose();
    audio.close();
    playhead.dispose();
    selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: context.qin.highContrast
          ? context.qin.background
          : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      title: PageTitle(c.text('乐谱回顾', 'Score review')),
      actions: [
        IconButton(
          key: const ValueKey('review-options'),
          tooltip: c.text('回放设置', 'Replay settings'),
          onPressed: busy ? null : options,
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (!context.qin.highContrast) ...[
          Image.asset(
            'assets/ui_images/${(qinPieceImage(widget.piece.id) ?? '08-completion-piano.png').replaceAll('.png', '.webp')}',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: context.qin.background),
          ),
          const ColoredBox(color: Color(0xd4fffaf1)),
        ],
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: qinPagePadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.record[c.chinese ? 'title_zh' : 'title_en']
                            as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      QinActionRow(
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('review-user-mode'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: userMode
                                  ? context.qin.soft
                                  : null,
                            ),
                            onPressed: !data.canReplay || busy
                                ? null
                                : () => switchMode(true),
                            icon: const Icon(Icons.touch_app_outlined),
                            label: Text(c.text('我的演奏', 'My performance')),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('review-demo-mode'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: !userMode
                                  ? context.qin.soft
                                  : null,
                            ),
                            onPressed: busy ? null : () => switchMode(false),
                            icon: const Icon(Icons.music_note),
                            label: Text(c.text('原谱示范', 'Reference')),
                          ),
                        ],
                      ),
                      if (!data.canReplay)
                        MetricNote(
                          c.text(
                            '旧记录未保存按键过程，可听原谱示范',
                            'Input timing was not saved; reference playback is available',
                          ),
                        ),
                      if (data.truncated)
                        MetricNote(
                          c.text(
                            '轨迹达到记录上限，回放仅含已录部分',
                            'Recording limit reached; replay contains the recorded portion',
                          ),
                        ),
                      if (!audio.audible)
                        MetricNote(
                          c.text(
                            '琴音已关闭 · 当前为静音回放',
                            'Piano sound is off · Silent replay',
                          ),
                          icon: Icons.volume_off_outlined,
                        ),
                      if (error != null)
                        QinStatus(text: error!, tone: QinTone.error),
                      for (var bar = 0; bar < measureKeys.length; bar++)
                        Padding(
                          key: measureKeys[bar],
                          padding: const EdgeInsets.only(top: 12),
                          child: QinPanel(
                            padding: const EdgeInsets.all(12),
                            child: ReviewStaff(
                              data: data,
                              measure: bar,
                              playhead: playhead,
                              selection: selection,
                              onNote: tapNote,
                              onRecordedNote: tapRecorded,
                              userMode: userMode,
                              preservePauses: preservePauses,
                              chinese: c.chinese,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: QinPanel(
                  padding: const EdgeInsets.all(12),
                  soft: true,
                  child: playbackControls(),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
