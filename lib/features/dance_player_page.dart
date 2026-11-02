import '../ui/qin_press.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../ui/qin_components.dart';
import '../ui/qin_theme.dart';
import 'dance_result_page.dart';

class DancePlayerPage extends StatefulWidget {
  const DancePlayerPage({
    super.key,
    required this.c,
    this.saveRecord,
    this.nowMilliseconds,
  });
  final AppController c;
  final Future<void> Function(Json)? saveRecord;
  final int Function()? nowMilliseconds;
  @override
  State<DancePlayerPage> createState() => _DancePlayerPageState();
}

class _DancePlayerPageState extends State<DancePlayerPage>
    with WidgetsBindingObserver {
  late final course = danceCourseFor(widget.c.chinese);
  late final ledgers = [for (final _ in course.parts) PlaybackLedger()];
  late final positions = List<Duration>.filled(
    course.parts.length,
    Duration.zero,
  );
  late final durations = List<Duration>.filled(
    course.parts.length,
    Duration.zero,
  );
  late final completed = List<bool>.filled(course.parts.length, false);
  final clock = Stopwatch()..start();
  final id = uuid();
  final started = DateTime.now();
  VideoPlayerController? video;
  Timer? timer;
  int selected = 0, generation = 0, previous = 0, wall = 0;
  bool wasPlaying = false,
      ready = false,
      foreground = true,
      busy = false,
      leaving = false,
      fullscreen = false,
      prompted = false,
      dialogOpen = false;
  bool scrubbing = false, resumeAfterScrub = false;
  VideoPlayerController? scrubController;
  Future<void> scrubPause = Future.value();
  String? failure;
  AppController get c => widget.c;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(milliseconds: 250), (_) => sample());
    unawaited(selectPart(0));
  }

  void sample({bool allowPrompt = true}) {
    final controller = video;
    if (controller == null || !ready) return;
    final value = controller.value,
        now = widget.nowMilliseconds?.call() ?? clock.elapsedMilliseconds;
    ledgers[selected].observe(
      from: previous,
      to: value.position.inMilliseconds,
      wallMs: now - wall,
      speed: value.playbackSpeed,
      playing: wasPlaying && !value.isBuffering && foreground && !scrubbing,
    );
    previous = value.position.inMilliseconds;
    wall = now;
    wasPlaying = value.isPlaying && !value.isBuffering && foreground;
    positions[selected] = value.position;
    durations[selected] = value.duration;
    if (mounted) {
      setState(() {
        if (value.hasError) {
          failure = c.text(
            '视频播放出错，可重试或结束并保存。',
            'Playback failed. Retry or finish and save.',
          );
        }
      });
    }
    if (value.isCompleted) completed[selected] = true;
    if (allowPrompt &&
        value.isCompleted &&
        !prompted &&
        foreground &&
        !busy &&
        !dialogOpen) {
      prompted = true;
      unawaited(partEnded(selected, generation));
    }
  }

  Future<void> selectPart(int index) async {
    if (busy || index < 0 || index >= course.parts.length) return;
    sample(allowPrompt: false);
    scrubbing = false;
    resumeAfterScrub = false;
    scrubController = null;
    final token = ++generation;
    final old = video;
    video = null;
    wasPlaying = false;
    setState(() {
      selected = index;
      ready = false;
      failure = null;
      prompted = false;
    });
    if (old != null) await old.dispose();
    if (!mounted || token != generation) return;
    final next = VideoPlayerController.asset(
      course.parts[index].asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    try {
      await next.initialize();
      if (!mounted || token != generation) {
        await next.dispose();
        return;
      }
      final position = positions[index] >= next.value.duration
          ? Duration.zero
          : positions[index];
      if (position > Duration.zero) await next.seekTo(position);
      if (!mounted || token != generation) {
        await next.dispose();
        return;
      }
      video = next;
      previous = position.inMilliseconds;
      wall = widget.nowMilliseconds?.call() ?? clock.elapsedMilliseconds;
      durations[index] = next.value.duration;
      setState(() => ready = true);
      if (foreground && !dialogOpen) await next.play();
    } catch (_) {
      if (video != next) await next.dispose();
      if (mounted && token == generation) {
        setState(
          () => failure = c.text(
            '视频无法打开，请重试。',
            'Unable to open video. Please retry.',
          ),
        );
      }
    }
  }

  Future<void> partEnded(int index, int token) async {
    if (!mounted) return;
    dialogOpen = true;
    final last = index == course.parts.length - 1;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.text('${course.parts[index].title}已播放结束', 'Video ended')),
        content: Text(
          c.text(
            last
                ? '可以结束并保存本次练习，也可以继续回看。'
                : '休息一下，准备好后继续${course.parts[index + 1].title}。',
            last
                ? 'Finish and save, or stay to review.'
                : 'Take a break, then continue to the next part.',
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('留在本页', 'Stay here')),
          ),
          QinFilledButton(
            key: const ValueKey('dance-next-part'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              c.text(
                last ? '结束并保存' : '下一部分',
                last ? 'Finish and save' : 'Next part',
              ),
            ),
          ),
        ],
      ),
    );
    dialogOpen = false;
    if (!mounted || token != generation || selected != index) return;
    if (action == true) {
      if (last) {
        await finish();
      } else {
        await selectPart(index + 1);
      }
    }
  }

  Future<void> seek(Duration position) async {
    final controller = video;
    if (controller == null || busy) return;
    sample(allowPrompt: false);
    wasPlaying = false;
    await controller.seekTo(position);
    if (video != controller) return;
    previous = controller.value.position.inMilliseconds;
    wall = widget.nowMilliseconds?.call() ?? clock.elapsedMilliseconds;
    if (position < controller.value.duration) prompted = false;
  }

  Future<void> beginScrub() async {
    final controller = video;
    if (controller == null || busy || scrubbing) return;
    sample(allowPrompt: false);
    scrubbing = true;
    resumeAfterScrub = controller.value.isPlaying;
    scrubController = controller;
    wasPlaying = false;
    scrubPause = controller.pause();
    await scrubPause;
  }

  Future<void> endScrub(Duration position) async {
    final controller = scrubController;
    if (controller == null) return;
    await scrubPause;
    if (!mounted || controller != video) return;
    await seek(position);
    if (!mounted || controller != video) return;
    final resume =
        resumeAfterScrub &&
        foreground &&
        !busy &&
        !dialogOpen &&
        position < controller.value.duration;
    scrubbing = false;
    resumeAfterScrub = false;
    scrubController = null;
    if (resume) await controller.play();
  }

  Future<void> changeRate(double rate) async {
    final controller = video;
    if (controller == null || busy) return;
    sample(allowPrompt: false);
    await controller.setPlaybackSpeed(rate);
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      sample(allowPrompt: false);
      foreground = false;
      resumeAfterScrub = false;
      wasPlaying = false;
      final controller = video;
      if (controller != null) unawaited(controller.pause());
    } else {
      foreground = true;
    }
  }

  Future<void> setFullscreen(bool value) async {
    setState(() => fullscreen = value);
    await SystemChrome.setPreferredOrientations(
      value
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> requestExit() async {
    if (busy || dialogOpen) return;
    sample(allowPrompt: false);
    wasPlaying = false;
    dialogOpen = true;
    final controller = video;
    if (controller != null) await controller.pause();
    if (!mounted) return;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.text('退出本次练习？', 'Exit this practice?')),
        content: Text(
          c.text(
            '退出不会保存本次训练记录。',
            'Your training record will not be saved if you exit.',
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        actions: [
          SizedBox(
            width: double.infinity,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: QinOutlinedButton(
                      key: const ValueKey('continue-dance'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        c.text('继续练习', 'Continue practice'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: QinFilledButton(
                      key: const ValueKey('confirm-exit-dance'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        c.text('退出', 'Exit'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    dialogOpen = false;
    if (exit == true && mounted) {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> finish() async {
    if (busy || !mounted) return;
    busy = true;
    sample(allowPrompt: false);
    wasPlaying = false;
    final controller = video;
    if (controller != null) await controller.pause();
    if (!mounted) return;
    final active = ledgers.fold<int>(0, (sum, l) => sum + l.activeMs);
    final record = <String, dynamic>{
      'session_id': id,
      'version': 2,
      'content_id': course.id,
      'content_version': 1,
      'title': course.title,
      'title_zh': course.id == chineseDanceCourse.id ? '新平衡舞步六式' : danceTitle,
      'title_en': course.id == chineseDanceCourse.id
          ? 'Six balance dance steps'
          : englishDanceCourse.title,
      'locale': c.locale,
      'started_utc_ms': started.toUtc().millisecondsSinceEpoch,
      'ended_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'utc_offset_minutes': started.timeZoneOffset.inMinutes,
      'active_ms': active,
      'covered_ms': ledgers.fold<int>(0, (sum, l) => sum + l.coveredMs),
      'position_ms': positions[selected].inMilliseconds,
      'reached_end': completed.every((v) => v),
      'confirmed': active > 0,
      'completion_source': 'USER_FINISH_AND_SAVE',
      'interrupted': false,
      'parts': [
        for (var i = 0; i < course.parts.length; i++)
          {
            'part_id': course.parts[i].id,
            'title': course.parts[i].title,
            'active_ms': ledgers[i].activeMs,
            'covered_ms': ledgers[i].coveredMs,
            'position_ms': positions[i].inMilliseconds,
            'duration_ms': durations[i].inMilliseconds,
            'reached_end': completed[i],
          },
      ],
    };
    // Replacing this route prevents a second save or a return to a sealed session.
    timer?.cancel();
    generation++;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;
    setState(() => leaving = true);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DanceResultPage(
          c: c,
          record: record,
          saveRecord: widget.saveRecord,
        ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    final controller = video;
    if (controller != null) unawaited(controller.dispose());
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Widget player() => DanceVideoSurface(
    controller: video,
    ready: ready,
    failure: failure,
    onRetry: () => selectPart(selected),
    onScrubStart: beginScrub,
    onScrubEnd: endScrub,
    onRate: changeRate,
    onToggle: () async {
      if (!foreground || busy || dialogOpen || scrubbing) return;
      final controller = video;
      if (controller == null) return;
      sample();
      wasPlaying = false;
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.isCompleted) await seek(Duration.zero);
        await controller.play();
      }
    },
    fullscreen: fullscreen,
    onFullscreen: () => setFullscreen(!fullscreen),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (popped, result) {
      if (!popped) {
        fullscreen ? unawaited(setFullscreen(false)) : unawaited(requestExit());
      }
    },
    child: Scaffold(
      backgroundColor: fullscreen ? Colors.black : null,
      appBar: fullscreen
          ? null
          : AppBar(
              leading: BackButton(onPressed: requestExit),
              title: Text(c.text('舞蹈跟练', 'Dance practice')),
            ),
      body: fullscreen
          ? SafeArea(child: player())
          : QinPageList(
              children: [
                if (course.parts.length > 1)
                  Row(
                    children: [
                      for (var i = 0; i < course.parts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: Semantics(
                            selected: selected == i,
                            child: QinOutlinedButton(
                              key: ValueKey('dance-part-$i'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 12,
                                ),
                                backgroundColor: selected == i
                                    ? context.qin.soft
                                    : context.qin.surface,
                                side: BorderSide(
                                  color: selected == i
                                      ? context.qin.primary
                                      : context.qin.edge,
                                  width: selected == i ? 2 : 1,
                                ),
                              ),
                              onPressed: busy ? null : () => selectPart(i),
                              child: Text(
                                course.parts[i].title,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) => SizedBox(
                    height:
                        box.maxWidth /
                        (ready ? video!.value.aspectRatio : 16 / 9),
                    child: player(),
                  ),
                ),
                const SizedBox(height: 20),
                QinFilledButton(
                  key: const ValueKey('finish-dance'),
                  onPressed: busy ? null : finish,
                  child: Text(c.text('结束并保存', 'Finish and save')),
                ),
              ],
            ),
    ),
  );
}

/// Gap between the control row and the seek bar; both are inside the video.
const danceControlsProgressGap = 0.0;

/// Touch layout height also controls the distance to the centre of the track.
const danceProgressTouchHeight = 20.0;

String danceRateLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toStringAsFixed(1) : rate.toString()}x';

class DanceVideoSurface extends StatefulWidget {
  const DanceVideoSurface({
    super.key,
    required this.controller,
    required this.ready,
    required this.failure,
    required this.onRetry,
    required this.onScrubStart,
    required this.onScrubEnd,
    required this.onRate,
    required this.onToggle,
    required this.fullscreen,
    required this.onFullscreen,
  });
  final VideoPlayerController? controller;
  final bool ready, fullscreen;
  final String? failure;
  final VoidCallback onRetry, onToggle, onFullscreen;
  final Future<void> Function() onScrubStart;
  final Future<void> Function(Duration) onScrubEnd;
  final Future<void> Function(double) onRate;
  @override
  State<DanceVideoSurface> createState() => _DanceVideoSurfaceState();
}

class _DanceVideoSurfaceState extends State<DanceVideoSurface> {
  bool controls = true, volume = false;
  double? dragging;
  final surfaceKey = GlobalKey(), volumeKey = GlobalKey();
  double volumeLeft = 0, volumeBottom = 0, volumeHeight = 100;
  String stamp(Duration d) =>
      '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  void didUpdateWidget(DanceVideoSurface old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.fullscreen != widget.fullscreen) {
      controls = true;
      volume = false;
      dragging = null;
    }
  }

  void toggleVolume() {
    if (volume) {
      setState(() => volume = false);
      return;
    }
    final root = surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    final button = volumeKey.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || button == null) return;
    final anchor = button.localToGlobal(Offset.zero, ancestor: root);
    setState(() {
      volumeLeft = (anchor.dx + button.size.width / 2 - 24).clamp(
        0,
        math.max(0, root.size.width - 48),
      );
      volumeBottom = root.size.height - anchor.dy + 6;
      volumeHeight = math.min(140, math.max(40, anchor.dy - 12));
      volume = true;
    });
  }

  ButtonStyle get iconStyle => IconButton.styleFrom(
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.all(8),
    foregroundColor: Colors.white,
  );
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller, v = controller?.value;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String a, String b) => zh ? a : b;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.fullscreen ? 0 : 16),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          key: surfaceKey,
          fit: StackFit.expand,
          children: [
            if (widget.ready && controller != null)
              FittedBox(
                fit: BoxFit.contain,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: v!.size.width,
                  height: v.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  controls = !controls;
                  if (!controls) volume = false;
                }),
                child: const SizedBox.expand(),
              ),
            ),
            if (widget.failure != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.failure!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      QinTextButton(
                        onPressed: widget.onRetry,
                        child: Text(t('重试', 'Retry')),
                      ),
                    ],
                  ),
                ),
              )
            else if (!widget.ready)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (widget.fullscreen)
              Positioned(
                left: 8,
                top: 8,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: QinIconButton(
                    key: const ValueKey('dance-fullscreen-back'),
                    style: iconStyle,
                    tooltip: t('返回', 'Back'),
                    onPressed: widget.onFullscreen,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            if (widget.ready && controller != null && controls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          key: const ValueKey('dance-controls-row'),
                          children: [
                            QinIconButton(
                              key: const ValueKey('dance-play'),
                              style: iconStyle,
                              tooltip: t(
                                v!.isPlaying ? '暂停' : '播放',
                                v.isPlaying ? 'Pause' : 'Play',
                              ),
                              onPressed: dragging != null
                                  ? null
                                  : widget.onToggle,
                              icon: Icon(
                                v.isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${stamp(Duration(milliseconds: dragging?.round() ?? v.position.inMilliseconds))} / ${stamp(v.duration)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            PopupMenuButton<double>(
                              key: const ValueKey('dance-rate'),
                              tooltip: t('播放倍率', 'Playback speed'),
                              color: context.qin.surface,
                              surfaceTintColor: Colors.transparent,
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: context.qin.edge),
                              ),
                              initialValue: v.playbackSpeed,
                              onOpened: () => setState(() => volume = false),
                              onSelected: (rate) => widget.onRate(rate),
                              itemBuilder: (_) => [
                                for (final rate in [0.75, 1.0, 1.25])
                                  PopupMenuItem<double>(
                                    value: rate,
                                    height: 60,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            danceRateLabel(rate),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: context.qin.ink,
                                                ),
                                          ),
                                        ),
                                        if (v.playbackSpeed == rate)
                                          Icon(
                                            Icons.check,
                                            color: context.qin.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                              child: SizedBox(
                                width: 72,
                                height: 48,
                                child: Center(
                                  child: Text(
                                    danceRateLabel(v.playbackSpeed),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            QinIconButton(
                              key: volumeKey,
                              style: iconStyle,
                              tooltip: t('音量', 'Volume'),
                              onPressed: toggleVolume,
                              icon: Icon(
                                v.volume == 0
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                            ),
                            QinIconButton(
                              key: const ValueKey('dance-fullscreen'),
                              style: iconStyle,
                              tooltip: t(
                                widget.fullscreen ? '退出全屏' : '全屏',
                                widget.fullscreen
                                    ? 'Exit fullscreen'
                                    : 'Fullscreen',
                              ),
                              onPressed: widget.onFullscreen,
                              icon: Icon(
                                widget.fullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: danceControlsProgressGap),
                        SizedBox(
                          height: danceProgressTouchHeight,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              key: const ValueKey('dance-progress'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              value:
                                  dragging ??
                                  v.position.inMilliseconds.toDouble().clamp(
                                    0,
                                    v.duration.inMilliseconds.toDouble(),
                                  ),
                              max: math
                                  .max(1, v.duration.inMilliseconds)
                                  .toDouble(),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white38,
                              onChangeStart: (value) {
                                setState(() => dragging = value);
                                unawaited(widget.onScrubStart());
                              },
                              onChanged: (value) =>
                                  setState(() => dragging = value),
                              onChangeEnd: (value) async {
                                await widget.onScrubEnd(
                                  Duration(milliseconds: value.round()),
                                );
                                if (mounted) setState(() => dragging = null);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (volume && controls && controller != null)
              Positioned(
                left: volumeLeft,
                bottom: volumeBottom,
                child: Material(
                  key: const ValueKey('dance-volume-panel'),
                  color: context.qin.surface,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.qin.edge),
                  ),
                  child: SizedBox(
                    width: 48,
                    height: volumeHeight,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        key: const ValueKey('dance-volume-slider'),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        value: v!.volume,
                        onChanged: (value) {
                          unawaited(controller.setVolume(value));
                          setState(() {});
                        },
                        activeColor: context.qin.primary,
                        inactiveColor: context.qin.line,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
