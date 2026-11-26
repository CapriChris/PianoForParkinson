import '../integration/training_capture.dart';
import 'capture_widgets.dart';
import '../ui/qin_press.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/piano_piece.dart';
import '../domain/piece_performance.dart';
import '../domain/scrolling_piece.dart';
import '../domain/piece_timing.dart';
import '../ui/text_scale.dart';
import '../ui/qin_theme.dart';
import 'keyboard.dart';
import 'piece_audio.dart';
import 'piece_backing_audio.dart';
import 'piece_result_page.dart';
import 'waterfall_score.dart';
import '../ui/qin_dialog.dart';

class PianoPerformancePage extends StatefulWidget {
  const PianoPerformancePage({
    super.key,
    required this.c,
    required this.piece,
    required this.tempo,
    this.capture,
    this.practiceMode = PiecePracticeMode.continuous,
  });
  final AppController c;
  final PianoPiece piece;
  final int tempo;
  final TrainingCapture? capture;
  final PiecePracticeMode practiceMode;
  @override
  State<PianoPerformancePage> createState() => _PianoPerformancePageState();
}

class _PianoPerformancePageState extends State<PianoPerformancePage>
    with SingleTickerProviderStateMixin {
  AppController get c => widget.c;
  int get tempo => widget.tempo.clamp(30, widget.piece.tempo);
  int? get highlightedKey {
    final index = player.currentIndex;
    if (index == null || player.elapsedUs >= player.noteEndUs(index)) {
      return null;
    }
    return player.targetKey;
  }

  late final player = ScrollingPiecePlayer(
    widget.piece,
    c.clock,
    tempo: tempo,
    training: true,
    practiceMode: widget.practiceMode,
  );
  late final PieceAudio audio = PieceAudio(
    c,
    onError: audioFailed,
    piece: widget.piece,
  );
  late final backing = PieceBackingAudio(c, widget.piece, onError: audioFailed);
  late final Ticker ticker;
  final frames = ValueNotifier<int>(0),
      keyboardInterruptions = ValueNotifier<int>(0);
  final autoStopped = <int>{};
  bool displayReady = false, starting = false, disposed = false;
  bool autoStartAttempted = false;
  bool finishing = false;
  DateTime? started;
  Animation<double>? routeAnimation;
  int epoch = 0;
  int resumeSecondsRemaining = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    c.holdCloudSync();
    ticker = createTicker((_) => frame());
    c.previewInterruptions.addListener(pause);
    unawaited(enterDisplay());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context)?.animation;
    if (next != routeAnimation) {
      routeAnimation?.removeStatusListener(routeStatus);
      routeAnimation = next;
      next?.addStatusListener(routeStatus);
    }
  }

  void routeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => maybeStart());
    }
  }

  Future<void> enterDisplay() async {
    try {
      await c.platform.call('setTrainingFullscreen', {'enabled': true});
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) setState(() => displayReady = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '暂时无法进入横屏，请返回重试。',
            'Unable to open landscape. Go back and retry.',
          ),
        );
      }
    }
  }

  void maybeStart() {
    if (!mounted ||
        !displayReady ||
        starting ||
        autoStartAttempted ||
        error != null ||
        player.mode != ScrollPieceMode.ready) {
      return;
    }
    final size = MediaQuery.sizeOf(context);
    if (size.width <= size.height ||
        ModalRoute.of(context)?.animation?.status == AnimationStatus.forward) {
      return;
    }
    autoStartAttempted = true;
    unawaited(confirmStart());
  }

  Future<void> confirmStart() async {
    final begin = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => QinDialog(
        title: Text(c.text('准备好开始弹奏了吗？', 'Ready to play?')),
        content: Text(
          c.text(
            '点击开始后倒数 3、2、1。长条落到琴键时按下，长条消失时松开。',
            'Start with a 3, 2, 1 count-in. Press as a bar reaches its key and release when its tail disappears.',
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('返回', 'Back')),
          ),
          QinFilledButton(
            key: const ValueKey('confirm-performance-start'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.text('开始', 'Start')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (begin == true) {
      await start();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> start() async {
    if (starting) return;
    autoStartAttempted = true;
    setState(() => starting = true);
    final token = ++epoch;
    try {
      await audio.stop();
      if (!mounted || token != epoch) return;
      await backing.prepare(tempo);
      if (!mounted || token != epoch) return;
      keyboardInterruptions.value++;
      autoStopped.clear();
      player.elapsedUs = -player.atTick(4 * widget.piece.ticksPerBeat);
      for (var count = 3; count > 0; count--) {
        setState(() => resumeSecondsRemaining = count);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || token != epoch) return;
      }
      resumeSecondsRemaining = 0;
      player.start(leadBeats: 4);
      unawaited(widget.capture?.setRunning(true));
      await backing.start(player);
      if (!mounted || token != epoch) return;
      started = DateTime.now();
      if (!ticker.isActive) ticker.start();
      error = null;
    } catch (_) {
      if (mounted) {
        error = c.text('暂时无法开始，请返回重试。', 'Unable to start. Go back and retry.');
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  void frame() {
    if (!mounted) return;
    final before = player.currentIndex, mode = player.mode;
    final beforeHighlight = highlightedKey;
    final beforeUs = player.elapsedUs;
    final previousPointers = Map.of(player.pointers);
    final wasWaiting = player.waitingForKey;
    player.tick();
    for (final entry in previousPointers.entries) {
      if (!player.pointers.containsKey(entry.key)) {
        audio.note(entry.value.key, false, entry.key);
      }
    }
    if (!wasWaiting && player.waitingForKey) keyboardInterruptions.value++;
    backing.sync(player);
    for (final p in player.pointers.entries) {
      final index = p.value.noteIndex;
      if (index != null &&
          player.elapsedUs >= player.noteEndUs(index) &&
          autoStopped.add(p.key)) {
        player.soundOff(p.key);
        audio.note(p.value.key, false, p.key);
      }
    }
    if (player.mode == ScrollPieceMode.complete) {
      ticker.stop();
      keyboardInterruptions.value++;
      unawaited(finish());
    } else if (player.waitingForKey && ticker.isActive) {
      ticker.stop();
    }
    frames.value++;
    if (before != player.currentIndex ||
        beforeHighlight != highlightedKey ||
        mode != player.mode ||
        wasWaiting != player.waitingForKey ||
        (beforeUs < -PieceTiming.onsetToleranceUs &&
            player.elapsedUs >= -PieceTiming.onsetToleranceUs)) {
      setState(() {});
    }
  }

  Future<void> finish() async {
    if (finishing) return;
    finishing = true;
    final record = PiecePerformance.completed(
      player,
      started ?? DateTime.now(),
    );
    unawaited(
      widget.capture?.finish(
        record['session_id'] as String,
        'PIECE_PERFORMANCE',
      ),
    );
    await audio.stop().catchError((_) {});
    await backing.stop().catchError((_) {});
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PieceResultPage(c: c, record: record),
      ),
    );
  }

  void pause() {
    ++epoch;
    resumeSecondsRemaining = 0;
    if (player.mode == ScrollPieceMode.ready && !starting) return;
    if (player.mode == ScrollPieceMode.ready) {
      autoStartAttempted = true;
      player.start(leadBeats: 4);
    }
    player.pause();
    unawaited(widget.capture?.setRunning(false));
    if (ticker.isActive) ticker.stop();
    keyboardInterruptions.value++;
    unawaited(audio.stop().catchError((_) {}));
    unawaited(backing.stop().catchError((_) {}));
    if (mounted && !disposed) setState(() {});
    if (player.mode == ScrollPieceMode.complete) unawaited(finish());
  }

  Future<void> resume() async {
    if (starting) return;
    setState(() => starting = true);
    final token = ++epoch;
    try {
      await audio.stop();
      if (!mounted || token != epoch) return;
      await backing.prepare(tempo);
      if (!mounted || token != epoch) return;
      // Keep the score frozen while the user prepares to play again.
      for (var beat = 3; beat > 0; beat--) {
        setState(() => resumeSecondsRemaining = beat);
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted || token != epoch) return;
      }
      resumeSecondsRemaining = 0;
      player.resume();
      unawaited(widget.capture?.setRunning(true));
      await backing.start(player);
      if (!mounted || token != epoch) return;
      backing.sync(player);
      if (player.mode == ScrollPieceMode.running && !ticker.isActive) {
        ticker.start();
      }
    } catch (_) {
      audioFailed();
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  void audioFailed() {
    pause();
    if (mounted) {
      setState(
        () => error = c.text(
          '琴音暂时不可用，请返回重试。',
          'Piano audio is unavailable. Go back and retry.',
        ),
      );
    }
  }

  @override
  void dispose() {
    c.releaseCloudSync();
    disposed = true;
    unawaited(widget.capture?.discard());
    ++epoch;
    routeAnimation?.removeStatusListener(routeStatus);
    c.previewInterruptions.removeListener(pause);
    ticker.dispose();
    audio.close();
    backing.close();
    frames.dispose();
    keyboardInterruptions.dispose();
    unawaited(
      c.platform
          .call('setTrainingFullscreen', {'enabled': false})
          .catchError((_) => <String, dynamic>{}),
    );
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => maybeStart());
    final playing =
        player.mode == ScrollPieceMode.running &&
        player.elapsedUs >= -PieceTiming.onsetToleranceUs &&
        !starting;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, size) {
            final keyboardHeight = (size.maxHeight * .44).clamp(90.0, 164.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      QinIconButton(
                        key: const ValueKey('performance-back'),
                        tooltip: c.text('返回', 'Back'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      CaptureIndicator(capture: widget.capture),
                      const Spacer(),
                      if (player.mode == ScrollPieceMode.running ||
                          player.mode == ScrollPieceMode.paused)
                        QinIconButton(
                          key: const ValueKey('performance-pause'),
                          tooltip: c.text(
                            player.mode == ScrollPieceMode.paused ? '继续' : '暂停',
                            player.mode == ScrollPieceMode.paused
                                ? 'Continue'
                                : 'Pause',
                          ),
                          onPressed: starting
                              ? null
                              : player.mode == ScrollPieceMode.paused
                              ? resume
                              : pause,
                          icon: Icon(
                            player.mode == ScrollPieceMode.paused
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 12, 12),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: keyboardHeight,
                          child: WaterfallKeyBases(
                            count: widget.piece.keyCount,
                            player: player,
                            frames: frames,
                            showCues: resumeSecondsRemaining == 0,
                          ),
                        ),
                        Positioned.fill(
                          bottom: keyboardHeight / 2,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: WaterfallScore(
                                  player: player,
                                  frames: frames,
                                  chinese: c.chinese,
                                  keyOverlap: keyboardHeight / 2,
                                  showCues: resumeSecondsRemaining == 0,
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: frames,
                                    builder: (context, _, _) {
                                      final text = player.waitingForKey
                                          ? c.text(
                                              '请按下亮起的琴键',
                                              'Press the highlighted key',
                                            )
                                          : player.elapsedUs >=
                                                    player.totalUs &&
                                                player.pointers.isNotEmpty
                                          ? c.text(
                                              '请松开琴键以完成训练',
                                              'Release the keys to finish',
                                            )
                                          : '';
                                      if (text.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Align(
                                        alignment: Alignment.topCenter,
                                        child: Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                            text,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              if (resumeSecondsRemaining > 0)
                                Positioned.fill(
                                  child: Center(
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        c.text(
                                          '准备继续 · $resumeSecondsRemaining',
                                          'Get ready · $resumeSecondsRemaining',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium,
                                      ),
                                    ),
                                  ),
                                ),
                              if (error != null)
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: context.qin.background,
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          error!,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: keyboardHeight,
                          child: PianoKeyboard(
                            count: widget.piece.keyCount,
                            splitZones: false,
                            externalKeyBases: true,
                            labels: widget.piece.keyLabels,
                            showKeyMarks: false,
                            feedbackParticles: false,
                            noteDegrees: [
                              for (var i = 0; i < widget.piece.keyCount; i++)
                                widget.piece.keyStep(i) % 7,
                            ],
                            active: {
                              for (var i = 0; i < widget.piece.keyCount; i++) i,
                            },
                            highlighted: highlightedKey,
                            highlightWhileLocked: true,
                            locked: !playing,
                            textScale:
                                (musicTextScalerOf(context).scale(1) * 1000)
                                    .round(),
                            interruptions: keyboardInterruptions,
                            onDown: (pointer, key, disabled, coordinates) {
                              if (key == null) return;
                              if (!player.down(pointer, key)) return;
                              autoStopped.remove(pointer);
                              audio.note(key, true, pointer);
                              backing.sync(player);
                              if (!player.waitingForKey && !ticker.isActive) {
                                ticker.start();
                              }
                              frames.value++;
                              setState(() {});
                            },
                            onUp: (pointer, key, cancel, coordinates) {
                              if (cancel) {
                                pause();
                                return;
                              }
                              player.up(pointer);
                              audio.note(key ?? 0, false, pointer);
                              autoStopped.remove(pointer);
                              frames.value++;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
