import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart';
import '../ui/text_scale.dart';
import '../ui/qin_components.dart';
import '../ui/qin_theme.dart';
import '../app/page_title.dart';
import '../domain/intro_lessons.dart';
import 'key_duration_guide.dart';
import 'keyboard.dart';
import 'spoken_text.dart';
import 'lesson_beat_timeline.dart';

class IntroLessonsPage extends StatefulWidget {
  const IntroLessonsPage({super.key, required this.c});
  final AppController c;
  @override
  State<IntroLessonsPage> createState() => _IntroLessonsPageState();
}

class _IntroLessonsPageState extends State<IntroLessonsPage> {
  late Future<Set<String>> progress;
  AppController get c => widget.c;
  @override
  void initState() {
    super.initState();
    progress = c.repository.completedLessons();
  }

  Widget hero(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: context.qin.highContrast
            ? ColoredBox(color: context.qin.surface)
            : Image.asset(
                'assets/ui_images/09-tutorial-hero.webp',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.qin.background),
              ),
      ),
      if (!context.qin.highContrast)
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xf2fffaf0),
                  Color(0xccfffaf0),
                  Color(0x22fffaf0),
                ],
                stops: [0, .50, 1],
              ),
            ),
          ),
        ),
      ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: qinShortLandscape(context)
              ? 190
              : (MediaQuery.sizeOf(context).height * .40).clamp(240.0, 340.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.text('入门教学', 'Introductory lessons'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.text('从零开始，打好基础。', 'Start with the basics.'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.text(
                        '在简单的练习中，\n感受钢琴的美好。',
                        'Discover the joy of piano\none step at a time.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.qin.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<Set<String>>(
        future: progress,
        builder: (context, snapshot) => QinPageList(
          padding: EdgeInsets.zero,
          children: [
            hero(context),
            Padding(
              padding: qinPagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasError) ...[
                    QinStatus(
                      tone: QinTone.warning,
                      text: c.text(
                        '完成标记读取失败，可以继续学习。',
                        'Completion marks could not be loaded. You can still learn.',
                      ),
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          progress = c.repository.completedLessons();
                        }),
                        child: Text(c.text('重试', 'Retry')),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  for (final lesson in IntroLesson.all) ...[
                    Semantics(
                      selected: snapshot.data?.contains(lesson.id) == true,
                      child: PracticeCard(
                        key: ValueKey(lesson.id),
                        artwork: lesson.id == 'T1'
                            ? '15-play-and-wait.png'
                            : lesson.id == 'T2'
                            ? '19-low-high-piano.png'
                            : '16-metronome.png',
                        icon: lesson.id == 'T1'
                            ? Icons.touch_app_outlined
                            : lesson.id == 'T2'
                            ? Icons.piano_outlined
                            : Icons.av_timer_outlined,
                        title: c.chinese ? lesson.zh : lesson.en,
                        completed: snapshot.data?.contains(lesson.id) == true,
                        subtitle: c.text(
                          switch (lesson.id) {
                            'T1' => '认识琴键，听见琴声',
                            'T2' => '感受琴键的高低音变化',
                            _ => '在节拍中弹奏和等待',
                          },
                          switch (lesson.id) {
                            'T1' => 'Know the keys, hear the sound',
                            'T2' => 'Feel the high and low notes',
                            _ => 'Play and wait for the beat',
                          },
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  IntroLessonPage(c: c, lesson: lesson),
                            ),
                          );
                          if (mounted) {
                            setState(() {
                              progress = c.repository.completedLessons();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
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

class IntroLessonPage extends StatefulWidget {
  const IntroLessonPage({super.key, required this.c, required this.lesson});
  final AppController c;
  final IntroLesson lesson;
  @override
  State<IntroLessonPage> createState() => _IntroLessonPageState();
}

class _IntroLessonPageState extends State<IntroLessonPage>
    with WidgetsBindingObserver {
  AppController get c => widget.c;
  int page = 0, keyboardEpoch = 0, demoPositionMs = 0;
  LessonDemo? demo;
  int? highlight, heldKey;
  final held = <int>{};
  final scroll = ScrollController();
  int? startedUs;
  int get elapsedMs =>
      startedUs == null ? 0 : (c.clock.now - startedUs!) ~/ 1000;
  Timer? ticker;
  bool demonstrating = false, saving = false, audioFailed = false;
  String? saveError;
  String get rule =>
      c.chinese ? widget.lesson.rules[page].zh : widget.lesson.rules[page].en;
  bool get rhythm => widget.lesson.id == 'T3';
  double get holdProgress => (elapsedMs / 400).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.previewInterruptions.addListener(interrupted);
    if (rhythm) {
      unawaited(setLessonFullscreen(true));
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }
  }

  Future<void> setLessonFullscreen(bool enabled) async {
    try {
      await c.platform.call('setTrainingFullscreen', {'enabled': enabled});
    } catch (_) {
      // Keep the lesson usable when the platform cannot hide system bars.
    }
  }

  void interrupted() {
    stop();
    if (mounted) setState(() {});
  }

  void sound(Future<void> operation) {
    unawaited(
      operation.catchError((Object _) {
        if (mounted) setState(() => audioFailed = true);
      }),
    );
  }

  void stop({bool completed = false}) {
    ticker?.cancel();
    startedUs = null;
    demonstrating = false;
    highlight = heldKey = null;
    if (!completed) demoPositionMs = 0;
    held.clear();
    keyboardEpoch++;
    sound(c.stopPreview());
    sound(c.stopSpeech());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      stop();
      if (mounted) setState(() {});
    }
  }

  void demonstrate() {
    stop();
    demo = LessonDemo.create(widget.lesson.id, page);
    final sequence = demo!.notes;
    const interval = LessonDemo.intervalMs;
    int lastStep = -1;
    bool released = false;
    demonstrating = true;
    startedUs = c.clock.now;
    void update() {
      final ms = elapsedMs;
      demoPositionMs = ms.clamp(0, demo!.durationMs);
      final step = ms ~/ interval;
      if (step >= sequence.length) {
        setState(() => stop(completed: true));
        return;
      }
      if (step != lastStep) {
        lastStep = step;
        released = false;
        highlight = sequence[step];
        if (rhythm) sound(c.preview(7, true, pointer: -101));
        if (highlight != null) {
          sound(c.preview(highlight!, true, pointer: -100));
        }
      }
      if (!released && ms % interval >= demo!.holdMs) {
        released = true;
        if (rhythm) sound(c.preview(7, false, pointer: -101));
        if (highlight != null) {
          sound(c.preview(highlight!, false, pointer: -100));
        }
        highlight = null;
      }
      setState(() {});
    }

    update();
    ticker = Timer.periodic(const Duration(milliseconds: 40), (_) => update());
  }

  Future<void> finish() async {
    setState(() {
      stop();
      saving = true;
      saveError = null;
    });
    try {
      await c.completeIntroLesson(widget.lesson.id);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = c.text(
            '完成标记未保存，请重试；也可以退出后重看。',
            'Completion was not saved. Retry, or leave and repeat later.',
          );
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.previewInterruptions.removeListener(interrupted);
    stop();
    scroll.dispose();
    if (rhythm) {
      unawaited(setLessonFullscreen(false));
      unawaited(
        SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      );
    }
    super.dispose();
  }

  Widget lessonKeyboard({double height = 144}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      KeyDurationGuide(
        compact: rhythm && height < 144,
        count: 3,
        targetKey: demonstrating
            ? demo!.notes[(demoPositionMs ~/ LessonDemo.intervalMs).clamp(
                0,
                demo!.notes.length - 1,
              )]
            : heldKey,
        progress: demonstrating
            ? ((elapsedMs % 1500).clamp(0, demo!.holdMs) / 400).clamp(0.0, 1.0)
            : holdProgress,
        durationMs: 400,
      ),
      SizedBox(height: height < 144 ? 2 : 8),
      SizedBox(
        height: height,
        child: PianoKeyboard(
          key: ValueKey('$page-$keyboardEpoch'),
          count: 3,
          active: const {0, 1, 2},
          highlighted: highlight,
          demonstratingKeys: demonstrating && highlight != null
              ? {highlight!}
              : const {},
          demonstrationPulse: (
            keyboardEpoch,
            page,
            demoPositionMs ~/ LessonDemo.intervalMs,
          ),
          highlightWhileLocked: true,
          locked: demonstrating || saving,
          textScale: (musicTextScalerOf(context).scale(1) * 1000).round(),
          onDown: (p, k, disabled, xy) {
            if (k == null) return;
            held.add(p);
            heldKey = k;
            startedUs = c.clock.now;
            sound(c.preview(k, true, pointer: p));
            ticker?.cancel();
            ticker = Timer.periodic(const Duration(milliseconds: 40), (_) {
              if (mounted) setState(() {});
            });
            setState(() {});
          },
          onUp: (p, k, cancel, xy) {
            held.remove(p);
            if (k != null) sound(c.preview(k, false, pointer: p));
            if (held.isEmpty) {
              ticker?.cancel();
              startedUs = null;
              heldKey = null;
            }
            setState(() {});
          },
        ),
      ),
    ],
  );

  void turnPage(int delta) => setState(() {
    stop();
    saveError = null;
    page += delta;
    if (scroll.hasClients) scroll.jumpTo(0);
  });

  Widget lessonActions() => LayoutBuilder(
    builder: (context, constraints) {
      final actions = <Widget>[
        OutlinedButton.icon(
          onPressed: saving
              ? null
              : () {
                  if (demonstrating) {
                    setState(stop);
                  } else {
                    demonstrate();
                  }
                },
          icon: Icon(demonstrating ? Icons.stop : Icons.play_arrow),
          label: Text(
            demonstrating
                ? c.text('停止示范', 'Stop example')
                : c.text('观看示范', 'Watch example'),
          ),
        ),
        OutlinedButton(
          onPressed: saving || page == 0 ? null : () => turnPage(-1),
          child: Text(c.text('上一页', 'Previous page')),
        ),
        FilledButton(
          onPressed: saving
              ? null
              : page == 2
              ? finish
              : () => turnPage(1),
          child: Text(
            saving
                ? c.text('正在保存', 'Saving')
                : page == 2
                ? c.text('完成教学', 'Complete lesson')
                : c.text('下一页', 'Next page'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(c.text('退出教学', 'Exit lesson')),
        ),
      ];
      final minWidth = 120 * MediaQuery.textScalerOf(context).scale(1) + 40;
      final columns = math.min(
        actions.length,
        math.max(1, ((constraints.maxWidth + 8) / (minWidth + 8)).floor()),
      );
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      // On phones keep the paging pair together on the second row.
      final ordered = columns == 2
          ? [actions[0], actions[3], actions[1], actions[2]]
          : actions;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final action in ordered) SizedBox(width: width, child: action),
        ],
      );
    },
  );

  Widget guidance({bool compact = false}) => SpokenText(
    compact: compact,
    c: c,
    text: rule,
    enabled: !saving && !demonstrating,
    style: Theme.of(context).textTheme.titleSmall,
  );

  Widget audioNotice() => QinStatus(
    tone: QinTone.warning,
    text: c.text(
      '当前无琴音，仍可观看示范和试按琴键。',
      'Piano audio is unavailable or muted. You can still watch and try the keys.',
    ),
  );

  Widget compactRhythm(BuildContext context, BoxConstraints constraints) {
    final keyHeight = constraints.maxHeight < 400
        ? 96.0
        : (constraints.maxHeight * .30).clamp(96.0, 144.0);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final columns = math.min(
      4,
      math.max(1, ((constraints.maxWidth - 24) / (120 * scale + 48)).floor()),
    );
    final rows = (4 / columns).ceil();
    final actionBudget = rows * math.max(60, 25 * scale + 28) + (rows - 1) * 8;
    // The observation-only first page reserves the same space without keys,
    // so paging controls keep the same position throughout this lesson.
    final keyboardBudget = keyHeight + 18;
    final upper = <Widget>[
      guidance(compact: true),
      if (!c.soundEnabled || !c.audioReady || audioFailed) ...[
        audioNotice(),
        const SizedBox(height: 4),
      ],
      LessonBeatTimeline(
        page: page,
        elapsedMs: demoPositionMs,
        running: demonstrating,
        chinese: c.chinese,
        compact: true,
      ),
      if (saveError != null) QinStatus(text: saveError!, tone: QinTone.error),
    ];
    // In exceptionally short windows the whole lesson remains reachable.
    // Normal landscapes reserve the action row and keyboard outside scrolling.
    if (constraints.maxHeight < actionBudget + keyboardBudget + 64) {
      return SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...upper,
            const SizedBox(height: 4),
            lessonActions(),
            if (page > 0) ...[
              const SizedBox(height: 4),
              lessonKeyboard(height: keyHeight),
            ] else
              SizedBox(height: keyboardBudget + 4),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: upper,
              ),
            ),
          ),
          const SizedBox(height: 4),
          lessonActions(),
          const SizedBox(height: 4),
          if (page > 0)
            lessonKeyboard(height: keyHeight)
          else
            SizedBox(height: keyboardBudget),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight:
          rhythm &&
              MediaQuery.sizeOf(context).width >
                  MediaQuery.sizeOf(context).height
          ? math.max(60, MediaQuery.textScalerOf(context).scale(24) * 1.3 + 16)
          : null,
      title: PageTitle(c.chinese ? widget.lesson.zh : widget.lesson.en),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text(
              '${page + 1} / 3',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) =>
            rhythm &&
                constraints.maxWidth >= 600 &&
                constraints.maxWidth > constraints.maxHeight
            ? compactRhythm(context, constraints)
            : QinActionPage(
                controller: scroll,
                actions: [lessonActions()],
                children: [
                  QinStepProgress(current: page + 1, total: 3),
                  const SizedBox(height: 16),
                  guidance(),
                  const SizedBox(height: 16),
                  if (!c.soundEnabled || !c.audioReady || audioFailed) ...[
                    audioNotice(),
                    const SizedBox(height: 16),
                  ],
                  if (rhythm) ...[
                    LessonBeatTimeline(
                      page: page,
                      elapsedMs: demoPositionMs,
                      running: demonstrating,
                      chinese: c.chinese,
                    ),
                    const SizedBox(height: 16),
                  ] else if (widget.lesson.id == 'T2') ...[
                    QinPanel(
                      soft: true,
                      child: Text(
                        c.text(
                          '低音  ←  1     2     3  →  高音',
                          'Lower  ←  1     2     3  →  Higher',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (!(rhythm && page == 0)) ...[
                    lessonKeyboard(),
                    const SizedBox(height: 12),
                    Text(
                      c.text(
                        '观看示范后可以自由试按，不计分。',
                        'After the example, try the keys freely without scoring.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (saveError != null) ...[
                    const SizedBox(height: 16),
                    QinStatus(text: saveError!, tone: QinTone.error),
                  ],
                ],
              ),
      ),
    ),
  );
}
