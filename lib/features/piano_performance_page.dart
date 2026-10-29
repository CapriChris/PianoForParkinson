import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/piano_piece.dart';
import '../domain/piece_performance.dart';
import '../domain/scrolling_piece.dart';
import '../ui/text_scale.dart';
import '../ui/qin_theme.dart';
import 'keyboard.dart';
import 'piece_audio.dart';
import 'piece_backing_audio.dart';
import 'piece_result_page.dart';
import 'scrolling_score.dart';

class PianoPerformancePage extends StatefulWidget {
  const PianoPerformancePage({
    super.key,
    required this.c,
    required this.piece,
    required this.tempo,
  });
  final AppController c;
  final PianoPiece piece;
  final int tempo;
  @override
  State<PianoPerformancePage> createState() => _PianoPerformancePageState();
}

class _PianoPerformancePageState extends State<PianoPerformancePage>
    with SingleTickerProviderStateMixin {
  AppController get c => widget.c;
  late final player = ScrollingPiecePlayer(
    widget.piece,
    c.clock,
    tempo: widget.tempo,
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
  String? error;
  @override
  void initState() {
    super.initState();
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
    unawaited(start());
  }

  Future<void> start() async {
    if (starting) return;
    autoStartAttempted = true;
    setState(() => starting = true);
    final token = ++epoch;
    try {
      await audio.stop();
      if (!mounted || token != epoch) return;
      await backing.prepare(widget.tempo);
      if (!mounted || token != epoch) return;
      keyboardInterruptions.value++;
      autoStopped.clear();
      player.start();
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
    player.tick();
    backing.sync(player);
    for (final p in player.pointers.entries) {
      final index = p.value.noteIndex;
      if (index != null &&
          player.elapsedUs >=
              player.atTick(widget.piece.notes[index].endTick) &&
          autoStopped.add(p.key)) {
        player.soundOff(p.key);
        audio.note(p.value.key, false, p.key);
      }
    }
    if (player.mode == ScrollPieceMode.complete) {
      ticker.stop();
      keyboardInterruptions.value++;
      unawaited(finish());
    }
    frames.value++;
    if (before != player.currentIndex || mode != player.mode) setState(() {});
  }

  Future<void> finish() async {
    if (finishing) return;
    finishing = true;
    final record = PiecePerformance.completed(
      player,
      started ?? DateTime.now(),
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
    if (player.mode == ScrollPieceMode.ready) {
      autoStartAttempted = true;
      player.start();
    }
    player.pause();
    if (ticker.isActive) ticker.stop();
    keyboardInterruptions.value++;
    unawaited(audio.stop().catchError((_) {}));
    unawaited(backing.stop().catchError((_) {}));
    if (mounted && !disposed) setState(() {});
  }

  Future<void> resume() async {
    if (starting) return;
    setState(() => starting = true);
    final token = ++epoch;
    try {
      await audio.stop();
      if (!mounted || token != epoch) return;
      await backing.prepare(widget.tempo);
      if (!mounted || token != epoch) return;
      player.resume();
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
    disposed = true;
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
        !player.leadingIn &&
        player.targetKey != null &&
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
                      IconButton(
                        key: const ValueKey('performance-back'),
                        tooltip: c.text('返回', 'Back'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Spacer(),
                      if (player.mode == ScrollPieceMode.running ||
                          player.mode == ScrollPieceMode.paused)
                        IconButton(
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
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ScrollingScore(
                                  player: player,
                                  frames: frames,
                                  chinese: c.chinese,
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
                        const SizedBox(height: 8),
                        SizedBox(
                          height: keyboardHeight,
                          child: PianoKeyboard(
                            count: widget.piece.keyCount,
                            splitZones: false,
                            labels: widget.piece.keyLabels,
                            showKeyMarks: false,
                            noteDegrees: [
                              for (var i = 0; i < widget.piece.keyCount; i++)
                                widget.piece.keyStep(i) % 7,
                            ],
                            active: {
                              for (var i = 0; i < widget.piece.keyCount; i++) i,
                            },
                            highlighted: player.targetKey,
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
                              frames.value++;
                              setState(() {});
                            },
                            onUp: (pointer, key, cancel, coordinates) {
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
