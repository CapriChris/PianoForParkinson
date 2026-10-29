import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../domain/contracts.dart';
import '../features/keyboard.dart';
import '../features/language_picker.dart';
import '../features/audio_volume_control.dart';
import '../features/text_size_control.dart';
import '../features/training_page.dart';
import '../features/trend_page.dart';
import '../features/switch_tutorial_page.dart';
import '../features/intro_lessons_page.dart';
import '../features/practice_steps.dart';
import '../features/touch_check_page.dart';
import '../features/song_library_page.dart';
import '../features/piano_pieces_page.dart';
import '../features/record_health_page.dart';
import '../features/piece_result_page.dart';
import '../domain/cognitive_tasks.dart';
import '../domain/history.dart';
import 'app_controller.dart';
import 'page_title.dart';
import '../ui/qin_theme.dart';
import '../ui/text_scale.dart';
import '../ui/qin_components.dart';
import '../ui/metric_visuals.dart';
import '../ui/qin_music_art.dart';

class PianoApp extends StatelessWidget {
  const PianoApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final contrast =
          controller.initialized &&
          controller.settings['high_contrast'] == true;
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: appName,
        themeAnimationDuration: Duration.zero,
        navigatorObservers: [controller.speechNavigationObserver],
        locale: Locale(controller.chinese ? 'zh' : 'en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final percent = controller.textScalePercent;
          final scaledMedia = percent == null
              ? media
              : media.copyWith(
                  textScaler: AppTextScaler(media.textScaler, percent),
                );
          final reduce =
              media.disableAnimations ||
              (controller.initialized &&
                  controller.settings['decorative_animation_enabled'] != true);
          return Theme(
            data: Theme.of(context).copyWith(
              expansionTileTheme: Theme.of(context).expansionTileTheme.copyWith(
                expansionAnimationStyle: reduce
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 180),
                      ),
              ),
              appBarTheme: Theme.of(context).appBarTheme.copyWith(
                toolbarHeight: qinShortLandscape(context)
                    ? (scaledMedia.textScaler.scale(24) * 1.3 + 28).clamp(
                        60.0,
                        double.infinity,
                      )
                    : scaledMedia.textScaler
                          .scale(72)
                          .clamp(72.0, double.infinity),
              ),
            ),
            child: MediaQuery(
              data: scaledMedia.copyWith(disableAnimations: reduce),
              child: child!,
            ),
          );
        },
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: qinTheme(highContrast: contrast),
        home: controller.error != null
            ? BootstrapError(c: controller)
            : !controller.initialized
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : controller.repository.profile['onboarding_completed'] == 0
            ? Onboarding(c: controller)
            : HomePage(c: controller),
      );
    },
  );
}

class BootstrapError extends StatelessWidget {
  const BootstrapError({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const PageTitle(appName)),
    body: SafeArea(
      child: QinPageList(
        children: [
          QinEmptyState(
            icon: Icons.music_off_outlined,
            title: c.text('暂时无法打开练习', 'Practice is unavailable'),
            message: c.text(
              '记录不会被自动清除，请重试。',
              'Your records will not be cleared. Please retry.',
            ),
            action: FilledButton(
              onPressed: c.busy ? null : c.initialize,
              child: Text(c.text('重试', 'Retry')),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: c.busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => RecordHealthPage(c: c)),
                  ),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(
              c.text('只读检查本机记录', 'Inspect local records without changes'),
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text(c.text('技术详情', 'Technical details')),
            children: [
              SelectableText(
                c.error ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, required this.c});
  final AppController c;
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  int step = 0;
  AppController get c => widget.c;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && step > 0) setState(() => step--);
    },
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 20,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: 0,
                          right: -20,
                          // Increase this factor to enlarge the background art.
                          width: constraints.maxWidth * 1.0,
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: Image.asset(
                                step == 1
                                    ? 'assets/ui_images/33-onboarding-music-flowers.webp'
                                    : 'assets/ui_images/32-onboarding-piano-flowers.webp',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 210,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  step == 0
                                      ? c.text(
                                          '欢迎来到\n琴伴',
                                          'Welcome to\nPiano Companion',
                                        )
                                      : step == 1
                                      ? c.text(
                                          '从一个音，\n开始',
                                          'Start with\none note',
                                        )
                                      : c.text(
                                          '找到适合\n自己的节奏',
                                          'Find your\nown rhythm',
                                        ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        shadows: [
                                          Shadow(
                                            color: context.qin.background,
                                            blurRadius: 12,
                                          ),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                            QinStepProgress(
                              current: step + 1,
                              total: 3,
                              label: c.text(
                                '第 ${step + 1} 步，共 3 步',
                                'Step ${step + 1} of 3',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (step == 0) ...[
                      Text(
                        '选择语言 / Choose language',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      for (final entry in {
                        'zh-Hans': '简体中文',
                        'en': 'English',
                      }.entries) ...[
                        _OnboardingChoice(
                          buttonKey: ValueKey('language-${entry.key}'),
                          title: entry.value,
                          selected: c.locale == entry.key,
                          onPressed: () => c.updateSettings(locale: entry.key),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (step == 1) ...[
                      Text(
                        c.text('轻触琴键，听见一个音', 'Touch a key to hear a note'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        c.text(
                          '按住琴键再松开，听听钢琴的余音。',
                          'Hold and release a key to hear the piano decay.',
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 144,
                        child: PianoKeyboard(
                          interruptions: c.previewInterruptions,
                          count: MediaQuery.sizeOf(context).width < 400 ? 3 : 5,
                          active: const {0, 1, 2, 3, 4},
                          onDown: (p, k, d, xy) {
                            if (k != null) c.preview(k, true, pointer: p);
                          },
                          onUp: (p, k, cancel, xy) {
                            if (k != null) c.preview(k, false, pointer: p);
                          },
                        ),
                      ),
                    ],
                    if (step == 2) ...[
                      Text(
                        c.text('选择舒服的起点', 'Choose a comfortable start'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      _OnboardingChoice(
                        title: c.text('基础辅助', 'Gentle support'),
                        subtitle: c.text(
                          '短序列，更多提示',
                          'Short sequences and more guidance',
                        ),
                        selected: c.mode == 'ASSIST',
                        onPressed: () => c.updateSettings(mode: 'ASSIST'),
                      ),
                      const SizedBox(height: 12),
                      _OnboardingChoice(
                        title: c.text('认知挑战', 'Cognitive challenge'),
                        subtitle: c.text(
                          '稍长的序列，逐步挑战',
                          'Longer sequences, at your pace',
                        ),
                        selected: c.mode == 'CHALLENGE',
                        onPressed: () => c.updateSettings(mode: 'CHALLENGE'),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 32),
                    if (step > 0) ...[
                      OutlinedButton(
                        onPressed: () => setState(() => step--),
                        child: Text(c.text('上一步', 'Back')),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton(
                      onPressed: () async {
                        await c.stopPreview();
                        if (step < 2) {
                          setState(() => step++);
                        } else {
                          await c.updateSettings(onboard: true);
                        }
                      },
                      child: Text(
                        step == 2
                            ? c.text('开始使用', 'Get started')
                            : c.text('下一步', 'Next'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _OnboardingChoice extends StatelessWidget {
  const _OnboardingChoice({
    this.buttonKey,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onPressed,
  });
  final Key? buttonKey;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final artWidth = MediaQuery.sizeOf(context).width < 380 ? 120.0 : 145.0;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        key: buttonKey,
        onPressed: onPressed,
        clipBehavior: Clip.antiAlias,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? context.qin.soft : null,
          side: BorderSide(
            color: selected ? context.qin.primary : context.qin.line,
            width: selected ? 2 : 1,
          ),
          padding: EdgeInsets.zero,
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: 0,
              right: 0,
              width: artWidth,
              child: ExcludeSemantics(
                child: Image.asset(
                  selected
                      ? 'assets/ui_images/34-onboarding-selected-flowers.webp'
                      : 'assets/ui_images/35-onboarding-unselected-leaves.webp',
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 0, 16),
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.check_circle : Icons.circle_outlined,
                      color: selected ? context.qin.primary : context.qin.muted,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: selected
                                      ? context.qin.primary
                                      : context.qin.ink,
                                ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: artWidth * 0.65),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.c});
  final AppController c;
  static void returnHome(BuildContext context, AppController c) {
    c.homeNavigationRequests.value++;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool openingRecommendation = false;
  AppController get c => widget.c;
  void showHome() => selectTab(0);
  @override
  void initState() {
    super.initState();
    c.homeNavigationRequests.addListener(showHome);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.c != c) {
      oldWidget.c.homeNavigationRequests.removeListener(showHome);
      c.homeNavigationRequests.addListener(showHome);
    }
  }

  @override
  void dispose() {
    c.homeNavigationRequests.removeListener(showHome);
    super.dispose();
  }

  Future<void> open(String id, {String? songId, bool chooseSong = true}) async {
    if ((id == 'S1_GUIDED' || id == 'S2_RHYTHM') && !chooseSong) {
      final piece = c.content.pieceFor(songId);
      if (piece != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PianoPiecePage(c: c, piece: piece),
          ),
        );
        return;
      }
      try {
        await c.selectSong(songId);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                c.text(
                  '暂时无法选择旋律，请重试。',
                  'Unable to choose the melody. Please retry.',
                ),
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isDualTask(id)
            ? DualZoneEntryPage(c: c)
            : chooseSong && (id == 'S1_GUIDED' || id == 'S2_RHYTHM')
            ? SongLibraryPage(c: c, taskId: id)
            : InstructionPage(c: c, taskId: id),
      ),
    );
    if (mounted) await c.refreshRecommendations();
  }

  void selectTab(int value) {
    if (value == 0) {
      unawaited(c.refreshRecommendations());
    }
    setState(() => tab = value);
    if (value == 2) c.refreshHistory();
  }

  Future<void> openRecommendation() async {
    if (openingRecommendation) return;
    setState(() => openingRecommendation = true);
    try {
      if (c.recommendedTask == null || c.recommendationError != null) {
        await c.refreshRecommendations();
      }
      if (!mounted) return;
      final task = c.recommendedTask;
      if (c.recommendationError != null || task == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.recommendationError ??
                  c.text(
                    '暂无推荐，请稍后重试。',
                    'No recommendation yet. Please try again.',
                  ),
            ),
          ),
        );
        return;
      }
      await open(task);
    } finally {
      if (mounted) setState(() => openingRecommendation = false);
    }
  }

  Widget recommendationCard() {
    final task = c.recommendationError == null ? c.recommendedTask : null;
    final title = task != null
        ? taskTitle(task, c.chinese)
        : c.recommendationError != null
        ? c.text('推荐暂不可用，点击重试', 'Recommendation unavailable. Tap to retry')
        : c.text('正在准备推荐', 'Preparing your recommendation');
    return PracticeCard(
      key: const ValueKey('home-recommendation'),
      icon: Icons.music_note_outlined,
      artwork: qinPracticeImage(task ?? ''),
      eyebrow: c.text('今日推荐', 'Today’s pick'),
      title: title,
      highlighted: true,
      onTap: openingRecommendation ? null : openRecommendation,
    );
  }

  Widget saveNotice() => QinStatus(
    tone: QinTone.warning,
    text: c.text(
      '上次练习尚未全部保存。请重试保存后再开始新练习。',
      'Your last practice is not fully saved. Retry saving before starting another practice.',
    ),
    child: FilledButton.icon(
      onPressed: c.finishSave,
      icon: const Icon(Icons.save_outlined),
      label: Text(c.text('重试保存', 'Retry saving')),
    ),
  );

  Widget lessonsEntry() => PracticeCard(
    icon: Icons.school_outlined,
    title: c.text('入门教学', 'Introductory lessons'),
    subtitle: c.text('从零开始，打好基础', 'Start with keys, pitch and beat'),
    artwork: '21-practice-intro.png',
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => IntroLessonsPage(c: c)),
    ),
  );

  Widget piecesEntry() => PracticeCard(
    icon: Icons.piano_outlined,
    title: c.text('钢琴曲目', 'Piano pieces'),
    artwork: '13-open-score.png',
    subtitle: c.text('选择喜欢的乐曲弹奏', 'Choose a piece and start playing'),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PianoPiecesPage(c: c)),
    ),
  );

  Widget practiceHeader({bool limited = false}) => Stack(
    children: [
      Positioned.fill(
        child: context.qin.highContrast
            ? ColoredBox(color: context.qin.surface)
            : Image.asset(
                'assets/ui_images/11-practice-piano.webp',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.qin.surface),
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
                  Color(0xf5fffaf0),
                  Color(0xdcfffaf0),
                  Color(0x00fffaf0),
                ],
                stops: [0, .45, .85],
              ),
            ),
          ),
        ),
      if (limited)
        SingleChildScrollView(child: practiceHeaderContent())
      else
        practiceHeaderContent(),
    ],
  );

  Widget practiceHeaderContent() => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 210),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.text('练习', 'Practice'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  c.text(
                    '选择一种练习方式，\n在琴声中慢慢进步。',
                    'Choose a way to practice,\nat your own pace.',
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
  );

  Widget homeContent() => LayoutBuilder(
    builder: (context, constraints) {
      final contrast = context.qin.highContrast;
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      Widget contents() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              mainAxisSize: largeText ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 72),
                Text(
                  c.text('今天，\n弹一小段旋律', 'A little melody\nfor today'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: context.qin.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  c.text(
                    '在熟悉的琴键上，\n遇见更安静的自己。',
                    'At the familiar keys,\nfind a quieter moment.',
                  ),
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: context.qin.ink),
                ),
                if (c.hasPendingSave) ...[
                  const SizedBox(height: 16),
                  saveNotice(),
                ],
                if (!largeText) const Spacer(),
                const SizedBox(height: 24),
                recommendationCard(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('home-other-practices'),
                  onPressed: () => selectTab(1),
                  icon: const Icon(Icons.tune),
                  label: Text(c.text('其他训练', 'Other practices')),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: contrast
                        ? context.qin.surface
                        : const Color(0xfff2e5d3),
                    minimumSize: const Size.fromHeight(68),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          if (!contrast)
            Image.asset(
              'assets/ui_images/01-home-piano.webp',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  ColoredBox(color: context.qin.background),
            )
          else
            ColoredBox(color: context.qin.background),
          if (!contrast)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xc9fff8e9),
                    Color(0x45fff8e9),
                    Color(0x00fff8e9),
                  ],
                  stops: [0, .28, .55],
                ),
              ),
            ),
          SingleChildScrollView(
            child: largeText
                ? contents()
                : ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(child: contents()),
                  ),
          ),
        ],
      );
    },
  );

  Widget directory() {
    final entries = <(String, IconData, String)>[
      (
        'G1_MEMORY',
        Icons.queue_music_outlined,
        c.text('听一段旋律，尝试弹出', 'Try to play what you hear'),
      ),
      (
        'G2_INHIBITION',
        Icons.pause_circle_outline,
        c.text('跟随提示，准确弹奏', 'Follow the prompts and play'),
      ),
      ('G3_SWITCH', Icons.swap_horiz, c.text('按规则弹奏', 'Play by the rules')),
      (
        'S1_GUIDED',
        Icons.music_note_outlined,
        c.text('弹奏一小段旋律', 'Play a short melody'),
      ),
      (
        'S2_RHYTHM',
        Icons.av_timer_outlined,
        c.text('在稳定的节拍中前进', 'Advance in steady tempo'),
      ),
      (
        'M1_ALTERNATE',
        Icons.swap_horiz,
        c.text('跟随节拍，交替弹奏', 'Follow the beat, alternate playing'),
      ),
      (
        'M2_DUAL_ZONE',
        Icons.pan_tool_alt_outlined,
        c.text('左右手的默契练习', 'Two-hand coordination practice'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, size) {
        final columns =
            size.maxWidth >= 760 &&
                MediaQuery.textScalerOf(context).scale(1) <= 1.5
            ? 2
            : 1;
        final width = (size.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: PracticeCard(
                  artwork: qinPracticeImage(entry.$1),
                  icon: entry.$2,
                  title: taskTitle(entry.$1, c.chinese),
                  subtitle: entry.$3,
                  onTap: () => open(entry.$1),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: tab == 0
                ? homeContent()
                : tab == 2
                ? HistoryList(c: c, onPractice: () => selectTab(1))
                : LayoutBuilder(
                    builder: (context, bounds) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final desired = 210.0 + (scale - 1).clamp(0.0, 2.0) * 100;
                      final available = bounds.maxHeight * .55;
                      final height = desired.clamp(0.0, available);
                      return Column(
                        children: [
                          SizedBox(
                            height: height,
                            child: practiceHeader(
                              limited: scale > 1.5 || height < desired,
                            ),
                          ),
                          Expanded(
                            child: QinPageList(
                              key: ValueKey(tab),
                              maxWidth: 1120,
                              children: [
                                if (c.hasPendingSave) ...[
                                  saveNotice(),
                                  const SizedBox(height: 16),
                                ],
                                if (!c.allIntroLessonsCompleted) ...[
                                  lessonsEntry(),
                                  const SizedBox(height: 12),
                                ],
                                piecesEntry(),
                                const SizedBox(height: 12),
                                directory(),
                                if (c.allIntroLessonsCompleted) ...[
                                  const SizedBox(height: 12),
                                  lessonsEntry(),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          Positioned(
            top: 6,
            right: 8,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.qin.highContrast
                                ? context.qin.surface
                                : const Color(0xb3fffaf0),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.qin.highContrast
                                  ? context.qin.ink
                                  : const Color(0x80ffffff),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: c.text('设置', 'Settings'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsPage(c: c)),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: QinNavigationBar(
      selected: tab,
      labels: [
        c.text('首页', 'Home'),
        c.text('练习', 'Practice'),
        c.text('记录', 'History'),
      ],
      onSelected: selectTab,
    ),
  );
}

class PracticeCard extends StatelessWidget {
  const PracticeCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.artwork,
    this.highlighted = false,
    this.eyebrow,
    this.completed = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String artwork;
  final VoidCallback? onTap;
  final bool highlighted;
  final String? eyebrow;
  final bool completed;
  @override
  Widget build(BuildContext context) {
    final contrast = context.qin.highContrast;
    final showImage =
        !contrast &&
        MediaQuery.sizeOf(context).width >= 340 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    final dark = highlighted && !contrast;
    final foreground = dark ? Colors.white : context.qin.ink;
    final background = dark
        ? context.qin.primary
        : contrast
        ? context.qin.surface
        : const Color(0xfff4ebdf);
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: contrast ? context.qin.ink : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 104),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showImage)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width * .26).clamp(
                      86.0,
                      140.0,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/ui_images/${artwork.replaceAll('.png', '.webp')}',
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) =>
                              Center(child: Icon(icon, color: foreground)),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Center(
                      child: Icon(icon, color: foreground, size: 28),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (eyebrow != null) ...[
                          Text(
                            eyebrow!,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: foreground),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: foreground),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: dark
                                      ? Colors.white
                                      : context.qin.muted,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dark
                            ? Colors.white.withValues(alpha: .15)
                            : contrast
                            ? context.qin.surface
                            : const Color(0xffe9dfd2),
                        border: contrast
                            ? Border.all(color: context.qin.ink)
                            : null,
                      ),
                      child: Semantics(
                        label: completed
                            ? (Localizations.localeOf(context).languageCode ==
                                      'zh'
                                  ? '已完成'
                                  : 'Completed')
                            : null,
                        excludeSemantics: true,
                        child: Icon(
                          completed ? Icons.check : Icons.chevron_right,
                          color: completed ? context.qin.primary : foreground,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DualZoneEntryPage extends StatefulWidget {
  const DualZoneEntryPage({super.key, required this.c});
  final AppController c;
  @override
  State<DualZoneEntryPage> createState() => _DualZoneEntryPageState();
}

class _DualZoneEntryPageState extends State<DualZoneEntryPage> {
  bool checked = false;
  @override
  void initState() {
    super.initState();
    checked = widget.c.dualTouchCheckCompleted;
    unawaited(
      orient([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  @override
  void dispose() {
    unawaited(orient(DeviceOrientation.values));
    super.dispose();
  }

  Future<void> orient(List<DeviceOrientation> orientations) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {
      // The check page explains when the available window is too narrow.
    }
  }

  @override
  Widget build(BuildContext context) => checked
      ? InstructionPage(c: widget.c, taskId: 'M2_DUAL_ZONE')
      : TouchCheckPage(
          c: widget.c,
          onContinue: () => setState(() => checked = true),
        );
}

class InstructionPage extends StatelessWidget {
  const InstructionPage({super.key, required this.c, required this.taskId});
  final AppController c;
  final String taskId;
  @override
  Widget build(BuildContext context) {
    final blocked =
        ((isCognitiveTask(taskId) ||
                isBeatTask(taskId) ||
                isDualTask(taskId)) &&
            MediaQuery.of(context).accessibleNavigation) ||
        isDualTask(taskId) &&
            (MediaQuery.sizeOf(context).width < 600 ||
                (!c.dualTouchCheckCompleted &&
                    (c.capabilities['max_verified_touch_points'] as int? ?? 0) <
                        2));
    final songId = taskId == 'S1_GUIDED' || taskId == 'S2_RHYTHM'
        ? c.content.song['content_id'] as String
        : null;
    final title = songId == null
        ? taskTitle(taskId, c.chinese)
        : c.content.song['localized_title'][c.locale] as String;
    final artwork =
        (songId == null ? null : qinSongImage(taskId, songId)) ??
        qinPracticeImage(taskId);
    final steps = practiceSteps(taskId);
    return Scaffold(
      appBar: AppBar(title: PageTitle(title)),
      body: QinActionPage(
        actions: [
          FilledButton(
            onPressed: blocked || (!c.audioReady && c.soundEnabled)
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TrainingPage(c: c, taskId: taskId),
                    ),
                  ),
            child: Text(c.text('开始练习', 'Start practice')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await c.stopAllPlayback().catchError((_) {});
              if (!context.mounted) return;
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                constraints: isDualTask(taskId)
                    ? const BoxConstraints(maxWidth: double.infinity)
                    : null,
                builder: (_) => PreviewSheet(
                  c: c,
                  layout: isDualTask(taskId)
                      ? PreviewLayout.dualZone
                      : taskId == 'M1_ALTERNATE'
                      ? PreviewLayout.alternate
                      : PreviewLayout.standard,
                ),
              );
              await c.stopPreview();
            },
            icon: const Icon(Icons.touch_app_outlined),
            label: Text(c.text('试按琴键', 'Try the keys')),
          ),
        ],
        children: [
          if (!context.qin.highContrast) ...[
            LayoutBuilder(
              builder: (context, constraints) => QinArtwork(
                asset: artwork,
                height: (constraints.maxWidth / 1.7).clamp(
                  100.0,
                  qinShortLandscape(context) ? 160.0 : 300.0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          PracticeStepsPanel(c: c, steps: steps),
          const SizedBox(height: 16),
          if (taskId == 'G3_SWITCH') ...[
            OutlinedButton.icon(
              key: const ValueKey('open-switch-tutorial'),
              onPressed: blocked || (!c.audioReady && c.soundEnabled)
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SwitchTutorialPage(c: c),
                      ),
                    ),
              icon: const Icon(Icons.extension_outlined),
              label: Text(c.text('试玩', 'Try examples')),
            ),
            const SizedBox(height: 16),
          ],
          ListenableBuilder(
            listenable: c,
            builder: (context, _) => c.allIntroLessonsCompleted
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => IntroLessonsPage(c: c)),
                    ),
                    icon: const Icon(Icons.school_outlined),
                    label: Text(c.text('查看入门教学', 'Introductory lessons')),
                  ),
          ),
          if (!c.audioReady && c.soundEnabled)
            QinStatus(
              tone: QinTone.warning,
              text: c.text(
                '声音暂不可用，请在设置中关闭声音后使用视觉练习。',
                'Audio is unavailable. Turn sound off in Settings to use visual practice.',
              ),
            ),
          if (blocked)
            QinStatus(
              tone: QinTone.warning,
              text: isDualTask(taskId)
                  ? c.text(
                      '双区配合需要至少 600 dp 可用宽度，并通过系统双触点确认；读屏时使用逐音旋律练习。',
                      'Two-zone practice requires at least 600 dp width and two verified system touch points. Use guided notes with a screen reader.',
                    )
                  : c.text(
                      '读屏模式下请使用不计时的歌曲练习。',
                      'Use untimed melody practice with a screen reader.',
                    ),
            ),
        ],
      ),
    );
  }
}

enum PreviewLayout { standard, alternate, dualZone }

class PreviewSheet extends StatelessWidget {
  const PreviewSheet({
    super.key,
    required this.c,
    this.layout = PreviewLayout.standard,
  });
  final AppController c;
  final PreviewLayout layout;
  bool get alternate => layout == PreviewLayout.alternate;

  Widget keys({required int count, required Set<int> active}) => PianoKeyboard(
    interruptions: c.previewInterruptions,
    count: count,
    active: active,
    onDown: (p, k, d, xy) {
      if (k != null) c.preview(k, true, pointer: p);
    },
    onUp: (p, k, cancel, xy) {
      if (k != null) c.preview(k, false, pointer: p);
    },
  );

  Widget back(BuildContext context) => FilledButton(
    onPressed: () async {
      await c.stopPreview();
      if (context.mounted) Navigator.pop(context);
    },
    child: Text(c.text('返回说明', 'Back to guidance')),
  );

  @override
  Widget build(BuildContext context) {
    if (layout == PreviewLayout.dualZone) {
      final media = MediaQuery.of(context);
      final height = media.size.height - media.padding.vertical - 60;
      final trainingBodyHeight =
          media.size.height -
          media.viewPadding.bottom -
          (media.textScaler.scale(24) * 1.3 + 12).clamp(60.0, double.infinity);
      return SizedBox(
        height: height,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, size) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          Text(
                            c.text('试按 · 不计入记录', 'Try the keys · Not recorded'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            c.text(
                              '左右两区各选一键，试着同时按下。',
                              'Try pressing one key in each area at the same time.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(alignment: Alignment.center, child: back(context)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.text('左区', 'Left area'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Text(
                          c.text('右区', 'Right area'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: practiceKeyHeight(trainingBodyHeight),
                    child: keys(count: 6, active: const {0, 1, 2, 3, 4, 5}),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.text('试按 · 不计入记录', 'Try the keys · Not recorded'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: alternate ? 520 : null,
                height: 144,
                child: keys(
                  count: alternate
                      ? 2
                      : MediaQuery.sizeOf(context).width < 400
                      ? 3
                      : 5,
                  active: alternate ? const {0, 1} : const {0, 1, 2, 3, 4},
                ),
              ),
              const SizedBox(height: 24),
              back(context),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryList extends StatelessWidget {
  const HistoryList({super.key, required this.c, this.onPractice});
  final AppController c;
  final VoidCallback? onPractice;
  Widget header(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 70, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTitle(c.text('记录', 'History')),
          const SizedBox(height: 20),
          Text(
            c.text('每一次练习，都在这里', 'Your practice moments'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: context.qin.primary),
          ),
          const SizedBox(height: 8),
          Text(
            c.text(
              '看见自己的练习轨迹，\n积累每一点进步。',
              'See your practice journey,\none step at a time.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.qin.background),
        if (!context.qin.highContrast)
          Image.asset(
            'assets/ui_images/30-records-piano-flowers-clear.webp',
            fit: BoxFit.cover,
            alignment: Alignment.centerRight,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (!context.qin.highContrast)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xf5f8f7f1),
                  Color(0xc4f8f7f1),
                  Color(0x00f8f7f1),
                ],
                stops: [0, .43, .86],
              ),
            ),
          ),
        SingleChildScrollView(child: content),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final desired = 235.0 + (scale - 1).clamp(0.0, 2.0) * 100;
        final height = desired.clamp(0.0, bounds.maxHeight * .5);
        return Column(
          children: [
            SizedBox(height: height, child: header(context)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: c.refreshHistory,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: qinPagePadding(context),
                  itemCount: c.history.length + 2,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: context.qin.soft,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TrendPage(c: c),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: context.qin.primary,
                                      foregroundColor: context.qin.onPrimary,
                                      child: const Icon(
                                        Icons.bar_chart_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.text('练习趋势', 'Practice trends'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            c.text(
                                              '查看各项练习的表现变化',
                                              'See your practice progress',
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const QinCircleArrow(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            c.text('最近练习', 'Recent practice'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      );
                    }
                    if (i == c.history.length + 1) {
                      if (c.historyLoading) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (c.historyError != null) {
                        return QinStatus(
                          tone: QinTone.error,
                          text: c.text(
                            '记录暂时无法读取，请重试。',
                            'Records could not be read. Please retry.',
                          ),
                          child: OutlinedButton(
                            onPressed: c.history.isEmpty
                                ? c.refreshHistory
                                : c.loadMoreHistory,
                            child: Text(c.text('重试', 'Retry')),
                          ),
                        );
                      }
                      if (c.history.isEmpty) {
                        return QinEmptyState(
                          icon: Icons.history_outlined,
                          title: c.text('还没有练习记录', 'No practice records yet'),
                          message: c.text(
                            '完成一段练习后，可以在这里回看。',
                            'Complete a practice and return here to review it.',
                          ),
                          action: onPractice == null
                              ? null
                              : FilledButton(
                                  onPressed: onPractice,
                                  child: Text(
                                    c.text('选择练习', 'Choose a practice'),
                                  ),
                                ),
                        );
                      }
                      return c.historyHasMore
                          ? OutlinedButton(
                              onPressed: c.loadMoreHistory,
                              child: Text(c.text('加载更多', 'Load more')),
                            )
                          : Center(
                              child: Text(
                                c.text('已显示全部记录', 'All records shown'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            );
                    }
                    final item = c.history[i - 1];
                    if (item['record_unavailable'] == true) {
                      return QinEntryCard(
                        icon: Icons.info_outline,
                        title: c.text(
                          '有一条记录暂时无法展示',
                          'A record is temporarily unavailable',
                        ),
                        subtitle: c.text(
                          '原始数据已保留，可查看完整性检查。',
                          'Original data is preserved. Open the integrity check for details.',
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RecordHealthPage(c: c),
                          ),
                        ),
                      );
                    }
                    final date = recordedDate(item, 'started_utc_ms');
                    final completed = item['status'] == 'COMPLETED';
                    final piece = c.content.pieceFor(
                      item['content_id'] as String?,
                    );
                    final taskId = item['task_id'] as String;
                    Map<String, dynamic>? summary;
                    try {
                      final raw = item['result_json'];
                      if (raw is String) {
                        summary = jsonDecode(raw) as Map<String, dynamic>;
                      }
                    } catch (_) {
                      // Older records may not contain a readable summary.
                    }
                    final numerator = taskId == 'PIANO_PIECE'
                        ? (summary?['matched_notes'] as List?)?.length
                        : summary?['rates']?['primary']?['numerator'];
                    final denominator = taskId == 'PIANO_PIECE'
                        ? (summary?['total_notes'])
                        : summary?['rates']?['primary']?['denominator'];
                    final valid =
                        numerator is int &&
                        denominator is int &&
                        denominator > 0 &&
                        numerator >= 0 &&
                        numerator <= denominator;
                    final title = taskId == 'PIANO_PIECE'
                        ? piece?.title(c.locale) ??
                              c.text('钢琴曲目', 'Piano piece')
                        : taskTitle(taskId, c.chinese);
                    final artwork = piece != null
                        ? qinPieceImage(piece.id) ?? qinPracticeImage(taskId)
                        : qinSongImage(
                                taskId,
                                item['content_id'] as String? ?? '',
                              ) ??
                              qinPracticeImage(taskId);
                    return Material(
                      color: context.qin.surface,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ResultPage(c: c, record: item),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final compact =
                                constraints.maxWidth < 380 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.4;
                            final imageSize = compact ? 70.0 : 96.0;
                            return IntrinsicHeight(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 108,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: imageSize,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          context.qin.highContrast
                                              ? ColoredBox(
                                                  color: context.qin.soft,
                                                  child: Icon(
                                                    Icons.music_note,
                                                    color: context.qin.ink,
                                                  ),
                                                )
                                              : Image.asset(
                                                  'assets/ui_images/${artwork.replaceAll('.png', '.webp')}',
                                                  fit: BoxFit.cover,
                                                  excludeFromSemantics: true,
                                                  errorBuilder: (_, _, _) =>
                                                      const Center(
                                                        child: Icon(
                                                          Icons.music_note,
                                                        ),
                                                      ),
                                                ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              recordDateLabel(date),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              completed
                                                  ? c.text('已完成', 'Completed')
                                                  : c.text(
                                                      '部分练习',
                                                      'Partial practice',
                                                    ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: context.qin.primary,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Center(
                                      child: SizedBox(
                                        width: compact ? 62 : 82,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            valid
                                                ? '$numerator / $denominator'
                                                : '—',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: context.qin.primary,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Center(child: QinCircleArrow()),
                                    const SizedBox(width: 10),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.c, required this.record});
  final AppController c;
  final Json record;
  @override
  Widget build(BuildContext context) {
    if (record['record_unavailable'] == true) return RecordHealthPage(c: c);
    if (record['task_id'] == 'PIANO_PIECE') {
      return PieceResultPage(
        c: c,
        record: jsonDecode(record['result_json'] as String) as Json,
        alreadySaved: true,
      );
    }
    final summary = record['result_json'] == null
        ? null
        : jsonDecode(record['result_json'] as String) as Json;
    final rate = summary?['rates']['primary'] as Map?;
    final count = rate?['denominator'] as int? ?? 0;
    final memory = record['task_id'] == 'G1_MEMORY';
    final piece = c.content.pieceFor(record['content_id'] as String?);
    final actions = <Widget>[
      FilledButton(
        onPressed: () async {
          final taskId = record['task_id'] as String;
          if (piece != null) {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PianoPiecePage(c: c, piece: piece),
              ),
            );
            return;
          }
          if (taskId == 'S1_GUIDED' || taskId == 'S2_RHYTHM') {
            final id = record['content_id'];
            if (!c.content.songs.any((song) => song['content_id'] == id)) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SongLibraryPage(c: c, taskId: taskId),
                ),
              );
              return;
            }
            try {
              await c.selectSong(id as String);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      c.text(
                        '暂时无法选择旋律，请重试。',
                        'Unable to select the melody. Please retry.',
                      ),
                    ),
                  ),
                );
              }
              return;
            }
            if (!context.mounted) return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isDualTask(record['task_id'] as String)
                  ? DualZoneEntryPage(c: c)
                  : InstructionPage(c: c, taskId: record['task_id'] as String),
            ),
          );
        },
        child: Text(
          piece == null
              ? c.text('再练一次', 'Practice again')
              : c.text('打开新版曲目', 'Open updated piece'),
        ),
      ),
      OutlinedButton(
        onPressed: () => HomePage.returnHome(context, c),
        child: Text(c.text('返回首页', 'Home')),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: PageTitle(c.text('本次练习', 'Your practice'))),
      body: QinActionPage(
        actions: actions,
        children: [
          if ((summary?['quality_flags'] as List? ?? []).contains(
            'SESSION_RESOURCE_LIMIT',
          ))
            QinStatus(
              tone: QinTone.warning,
              text: c.text(
                '本次记录较多，已保存完成部分。准备好后可开启新一轮。',
                'This practice generated many records. Completed items were saved; start a new session when ready.',
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                record['status'] == 'COMPLETED'
                    ? Icons.check_circle_outline
                    : Icons.history_outlined,
                size: 28,
                color: context.qin.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  record['status'] == 'COMPLETED'
                      ? c.text('这一段，你完成了', 'You finished this practice')
                      : c.text('你的练习已记录', 'Your practice was recorded'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            taskTitle(record['task_id'] as String, c.chinese),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (summary != null) ...[
            MetricRateGraphic(
              label: primaryMetricTitle(record['task_id'] as String, c.chinese),
              numerator: rate?['numerator'] as int? ?? 0,
              denominator: count,
              chinese: c.chinese,
              hero: true,
            ),
            const SizedBox(height: 12),
            QinMetrics(
              values: [
                QinMetric(
                  c.text('已完成', 'Completed'),
                  '${summary['completed']} / ${summary['planned']}',
                  icon: Icons.checklist_rounded,
                  progress: (summary['planned'] as num) > 0
                      ? (summary['completed'] as num) /
                            (summary['planned'] as num)
                      : null,
                ),
                QinMetric(
                  c.text('有效练习时间', 'Active practice'),
                  c.text(
                    '${(summary['active_duration_us'] as int) ~/ 1000000} 秒',
                    '${(summary['active_duration_us'] as int) ~/ 1000000} s',
                  ),
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TrendPage(c: c, taskId: record['task_id'] as String),
              ),
            ),
            child: Text(c.text('查看练习趋势', 'View practice trends')),
          ),
          const SizedBox(height: 24),
          ExpansionTile(
            title: Text(c.text('详细训练表现', 'Practice details')),
            childrenPadding: const EdgeInsets.all(16),
            children: [
              if (summary != null) ...[
                for (final entry in resultRateLabels.entries)
                  if (summary['rates'][entry.key] is Map)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MetricRate(
                        c: c,
                        label: c.text(entry.value.$1, entry.value.$2),
                        value: summary['rates'][entry.key] as Json,
                        errorRate: errorRateIds.contains(entry.key),
                      ),
                    ),
                const SizedBox(height: 12),
                if (isBeatTask(record['task_id'] as String)) ...[
                  MetricNote(
                    c.text(
                      {
                            'metrics-2.0.0',
                            'metrics-2.1.0',
                          }.contains(record['metric_version'])
                          ? '每音按住至少 0.4 秒 · 短按另计'
                          : '按住时长不参与命中评分',
                      {
                            'metrics-2.0.0',
                            'metrics-2.1.0',
                          }.contains(record['metric_version'])
                          ? 'Hold each note ≥0.4 s · Short presses counted separately'
                          : 'Hold duration does not affect hits',
                    ),
                  ),
                  MetricCountBars(
                    title: c.text('命中节拍的位置', 'Timing of beat hits'),
                    counts: {
                      c.text('提前', 'Early'):
                          summary['beat_direction_counts']?['early'] as int? ??
                          0,
                      c.text('正好', 'On target'):
                          summary['beat_direction_counts']?['on_target']
                              as int? ??
                          0,
                      c.text(
                        '延后',
                        'Late',
                      ): summary['beat_direction_counts']?['late'] as int? ?? 0,
                    },
                  ),
                  MetricNote(
                    c.text(
                      '相对计划拍点 · 声音延迟未校准',
                      'Relative to planned beats · Audio latency uncalibrated',
                    ),
                  ),
                ],
                for (final entry in resultTimingLabels.entries)
                  if (summary['timing_groups']?[entry.key] is Map)
                    MetricTiming(
                      c: c,
                      label: entry.key == 'first_response_unassisted' && memory
                          ? c.text(
                              '首次有效按键（无帮助）',
                              'First response without assistance',
                            )
                          : c.text(entry.value.$1, entry.value.$2),
                      value: summary['timing_groups'][entry.key] as Json,
                      showCv: entry.key == 'alternate_hit_interval',
                    ),
                if (summary.containsKey('switch_median_difference')) ...[
                  if (summary['switch_median_difference'] is Map)
                    QinMetrics(
                      values: [
                        QinMetric(
                          c.text(
                            '切换 − 重复 · 中位时间差',
                            'Switch − repeat · Median gap',
                          ),
                          c.text(
                            '${(summary['switch_median_difference']['numerator_us'] / summary['switch_median_difference']['denominator'] / 1000).toStringAsFixed(1)} 毫秒',
                            '${(summary['switch_median_difference']['numerator_us'] / summary['switch_median_difference']['denominator'] / 1000).toStringAsFixed(1)} ms',
                          ),
                          icon: Icons.compare_arrows,
                        ),
                      ],
                    ),
                  MetricNote(
                    c.text(
                      '两类各需 5 个无帮助命中样本',
                      'Needs 5 unassisted hits in each group',
                    ),
                  ),
                ],
                if (isDualTask(record['task_id'] as String))
                  MetricNote(
                    c.text(
                      '含超过容差的正确双区响应 · 屏幕区域不代表真实左右手',
                      'Includes correct pairs above tolerance · Screen areas do not identify hands',
                    ),
                  ),
                if (memory)
                  MetricNote(
                    c.text(
                      '首次按键包括未完整正确的序列',
                      'First responses include incomplete or incorrect sequences',
                    ),
                  ),
                const SizedBox(height: 12),
                MetricCountBars(
                  title: c.text('操作记录 · 次数', 'Input events · Count'),
                  counts: {
                    for (final entry in resultErrorLabels.entries)
                      if (summary['error_counts']?[entry.key] is int)
                        c.text(entry.value.$1, entry.value.$2):
                            summary['error_counts'][entry.key] as int,
                  },
                ),
                if (summary['outcome_counts'] is Map) ...[
                  const SizedBox(height: 12),
                  MetricCountBars(
                    title: c.text('单项结果 · 次数', 'Item outcomes · Count'),
                    counts: {
                      for (final entry in resultOutcomeLabels.entries)
                        if (summary['outcome_counts'][entry.key] is int)
                          c.text(entry.value.$1, entry.value.$2):
                              summary['outcome_counts'][entry.key] as int,
                    },
                  ),
                ],
                const SizedBox(height: 12),
                QinMetrics(
                  values: [
                    if (summary['longest_full_correct_sequence'] is int)
                      QinMetric(
                        c.text('最长完整正确序列', 'Longest fully correct sequence'),
                        c.text(
                          '${summary['longest_full_correct_sequence']} 个音',
                          '${summary['longest_full_correct_sequence']} notes',
                        ),
                        icon: Icons.queue_music,
                      ),
                    for (final entry in resultSampleLabels.entries)
                      if (summary['sample_counts']?[entry.key] is int)
                        QinMetric(
                          c.text(entry.value.$1, entry.value.$2),
                          '${summary['sample_counts'][entry.key]}',
                          icon: Icons.scatter_plot_outlined,
                        ),
                  ],
                ),
                const SizedBox(height: 12),
                MetricCountBars(
                  title: c.text('辅助使用 · 次数', 'Assistance · Count'),
                  counts: {
                    for (final entry in resultHelpLabels.entries)
                      if (summary['assistance_counts']?[entry.key] is int)
                        c.text(entry.value.$1, entry.value.$2):
                            summary['assistance_counts'][entry.key] as int,
                  },
                ),
              ] else
                MetricNote(
                  c.text('此记录未保存详细指标', 'Detailed metrics were not saved'),
                ),
              MetricNote(
                c.text(
                  '仅描述本次操作，不代表康复效果',
                  'Practice performance only, not rehabilitation outcomes',
                ),
              ),
              ExpansionTile(
                title: Text(c.text('记录信息', 'Record information')),
                children: [
                  ListTile(
                    title: Text(c.text('参数版本', 'Parameter version')),
                    subtitle: Text('${record['parameter_profile_version']}'),
                  ),
                  ListTile(
                    title: Text(c.text('指标版本', 'Metric version')),
                    subtitle: Text('${record['metric_version']}'),
                  ),
                  ListTile(
                    title: Text(c.text('练习模式', 'Practice mode')),
                    subtitle: Text(
                      record['mode'] == 'ASSIST'
                          ? c.text('辅助', 'Assist')
                          : c.text('挑战', 'Challenge'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: context.qin.error),
            onPressed: () async {
              if (await confirm(
                context,
                c.text('删除这次练习记录？', 'Delete this practice record?'),
                c.text(
                  '这次记录及原始操作将从本机删除。',
                  'This record and its input events will be deleted from this device.',
                ),
                confirmLabel: c.text('删除记录', 'Delete record'),
                destructive: true,
              )) {
                await c.repository.delete(record['session_id'] as String);
                await c.refreshHistory();
                if (context.mounted) Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(c.text('删除这次记录', 'Delete this record')),
          ),
        ],
      ),
    );
  }
}

const errorRateIds = {
  'go_omission',
  'go_wrong_key',
  'go_extra_response',
  'no_go_commission',
  'beat_omission',
  'beat_wrong_key',
  'beat_extra_response',
};
const resultRateLabels = {
  'unassisted_primary': ('无帮助的正确率', 'Accuracy without assistance'),
  'assisted_primary': ('有帮助的正确率', 'Assisted accuracy'),
  'position_accuracy': ('位置正确率', 'Position accuracy'),
  'correct_actions': ('正确按键 / 全部响应', 'Correct presses / all responses'),
  'go_hit': ('弹奏信号命中', 'Go hits'),
  'go_omission': ('弹奏信号漏按', 'Go omissions'),
  'go_wrong_key': ('弹奏信号错键', 'Go wrong keys'),
  'go_extra_response': ('弹奏信号额外响应', 'Go extra responses'),
  'no_go_commission': ('等待信号误按', 'Wait commissions'),
  'no_go_correct': ('等待信号正确等待', 'Correct waits'),
  'rule_position': ('规则 A · 按位置', 'Rule A · Position'),
  'rule_shape': ('规则 B · 按图形', 'Rule B · Shape'),
  'switch': ('切换项正确率', 'Switch accuracy'),
  'non_switch': ('重复规则正确率', 'Repeat accuracy'),
  'beat_omission': ('漏拍', 'Missed beats'),
  'beat_wrong_key': ('错键', 'Wrong keys'),
  'beat_extra_response': ('额外响应', 'Extra responses'),
};
const resultTimingLabels = {
  'first_response': ('首次响应', 'First response'),
  'first_response_unassisted': (
    '命中反应时间（无帮助）',
    'Hit reaction time without assistance',
  ),
  'first_response_assisted': ('首次有效按键（有帮助）', 'First response with assistance'),
  'beat_error_absolute': ('绝对节拍误差', 'Absolute beat error'),
  'beat_error_absolute_unassisted': (
    '绝对节拍误差（无帮助）',
    'Absolute beat error without assistance',
  ),
  'alternate_hit_interval': ('连续命中间隔', 'Consecutive hit interval'),
  'dual_gap': ('双区响应时间差', 'Two-zone response gap'),
  'switch_unassisted': ('切换项用时（无帮助）', 'Switch time · Unassisted'),
  'non_switch_unassisted': ('重复规则用时（无帮助）', 'Repeat time · Unassisted'),
  'key_hold': ('按住时长', 'Key hold duration'),
  'window_duration': ('响应窗口用时', 'Response window duration'),
};
const resultErrorLabels = {
  'short_press': ('时值不足', 'Short presses'),
  'outside': ('键区外按键', 'Outside keys'),
  'disabled': ('非激活键', 'Inactive keys'),
  'overlap': ('重叠按键', 'Overlapping presses'),
  'extra': ('额外按键', 'Extra presses'),
  'out_of_window': ('窗口外按键', 'Out-of-window presses'),
  'omitted_positions': ('遗漏位置', 'Omitted positions'),
  'wrong_press': ('错键', 'Wrong presses'),
};
const resultOutcomeLabels = {
  'HIT': ('命中', 'Hit'),
  'OMISSION': ('漏按', 'Omission'),
  'WRONG_KEY': ('错键', 'Wrong key'),
  'EXTRA_RESPONSE': ('额外响应', 'Extra response'),
  'TOO_SHORT': ('时值不足', 'Too short'),
  'CORRECT_WITHHOLD': ('正确等待', 'Correct wait'),
  'COMMISSION': ('等待时误按', 'Wait commission'),
  'WRONG_OR_EXTRA': ('错键或额外响应', 'Wrong or extra'),
  'OUT_OF_SYNC': ('响应差超过容差', 'Above gap tolerance'),
};
const resultSampleLabels = {
  'valid': ('有效项', 'Valid items'),
  'unassisted': ('无帮助项', 'Unassisted items'),
  'assisted': ('有帮助项', 'Assisted items'),
  'interrupted': ('中断尝试', 'Interrupted attempts'),
  'invalid': ('无效尝试', 'Invalid attempts'),
  'response_actions': ('响应动作', 'Response actions'),
  'valid_go': ('有效弹奏信号', 'Valid go items'),
  'valid_no_go': ('有效等待信号', 'Valid wait items'),
};
const resultHelpLabels = {
  'help': ('主动帮助', 'Help used'),
  'policy_hint': ('策略高亮', 'Automatic highlights'),
  'interrupted_retry': ('中断重试', 'Interrupted retries'),
  'user_pause': ('主动暂停', 'User pauses'),
  'assisted_trials': ('有帮助项', 'Assisted items'),
};

class MetricRate extends StatelessWidget {
  const MetricRate({
    super.key,
    required this.c,
    required this.label,
    required this.value,
    this.errorRate = false,
  });
  final AppController c;
  final String label;
  final Json value;
  final bool errorRate;
  @override
  Widget build(BuildContext context) => MetricRateGraphic(
    label: label,
    numerator: value['numerator'] as int,
    denominator: value['denominator'] as int,
    chinese: c.chinese,
    errorRate: errorRate,
  );
}

class MetricTiming extends StatelessWidget {
  const MetricTiming({
    super.key,
    required this.c,
    required this.label,
    required this.value,
    this.showCv = false,
  });
  final AppController c;
  final String label;
  final Json value;
  final bool showCv;
  @override
  Widget build(BuildContext context) => MetricTimingGraphic(
    label: label,
    stats: value,
    chinese: c.chinese,
    showCv: showCv,
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String? confirmLabel,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '取消'
                  : 'Cancel',
            ),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: context.qin.error,
                    foregroundColor: context.qin.onPrimary,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel ??
                  (Localizations.localeOf(context).languageCode == 'zh'
                      ? '确认'
                      : 'Confirm'),
            ),
          ),
        ],
      ),
    ) ??
    false;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.c});
  final AppController c;

  Widget header(BuildContext context, {bool limited = false}) => Stack(
    children: [
      Positioned.fill(
        child: context.qin.highContrast
            ? ColoredBox(color: context.qin.surface)
            : Image.asset(
                'assets/ui_images/12-settings-flowers.webp',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
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
                  Color(0xf7fffaf0),
                  Color(0xe0fffaf0),
                  Color(0x00fffaf0),
                ],
                stops: [0, .42, .85],
              ),
            ),
          ),
        ),
      if (limited)
        SingleChildScrollView(child: headerContent(context))
      else
        headerContent(context),
    ],
  );

  Widget headerContent(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 150),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                c.text('设置', 'Settings'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget groupTitle(BuildContext context, IconData icon, String title) => Row(
    children: [
      Icon(icon, color: context.qin.primary, size: 26),
      const SizedBox(width: 12),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final desired = 150.0 + (scale - 1).clamp(0.0, 2.0) * 48;
            final height = desired.clamp(0.0, bounds.maxHeight * .45);
            return Column(
              children: [
                SizedBox(
                  height: height,
                  child: header(context, limited: height < desired),
                ),
                Expanded(
                  child: QinPageList(
                    padding: EdgeInsets.zero,
                    children: [
                      Padding(
                        padding: qinPagePadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            QinSectionTitle(
                              c.text('语言与练习', 'Language and practice'),
                            ),
                            QinPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  groupTitle(
                                    context,
                                    Icons.language,
                                    c.text('语言', 'Language'),
                                  ),
                                  const SizedBox(height: 12),
                                  LanguagePicker(c: c),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  groupTitle(
                                    context,
                                    Icons.school_outlined,
                                    c.text('体验模式', 'Practice mode'),
                                  ),
                                  ModePicker(c: c, descriptions: true),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            QinSectionTitle(c.text('声音', 'Sound')),
                            QinPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AudioVolumeControl(
                                    c: c,
                                    embedded: true,
                                    icon: Icons.piano_outlined,
                                    settingKey: 'gain_permille',
                                    title: c.text('琴键与节拍', 'Keys and beats'),
                                    sampleLabel: c.text(
                                      '试听琴键',
                                      'Test key sound',
                                    ),
                                    onSample: !c.soundEnabled || !c.audioReady
                                        ? null
                                        : () async {
                                            try {
                                              await c.preview(
                                                0,
                                                true,
                                                pointer: -900,
                                              );
                                              await Future<void>.delayed(
                                                const Duration(
                                                  milliseconds: 400,
                                                ),
                                              );
                                              await c.preview(
                                                0,
                                                false,
                                                pointer: -900,
                                              );
                                            } catch (_) {
                                              await c.stopPreview();
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  AudioVolumeControl(
                                    c: c,
                                    embedded: true,
                                    icon: Icons.record_voice_over_outlined,
                                    settingKey: 'speech_gain_permille',
                                    description:
                                        (c.capabilities['tts_locales']
                                                    as List? ??
                                                [])
                                            .any(
                                              (tag) => '$tag'.startsWith(
                                                c.chinese ? 'zh' : 'en',
                                              ),
                                            )
                                        ? null
                                        : c.text(
                                            '本机暂无对应的本地语音，文字提示仍可使用。',
                                            'No local voice for this language. Text guidance remains available.',
                                          ),
                                    title: c.text('语音提示', 'Spoken guidance'),
                                    sampleLabel: c.text(
                                      '试听语音',
                                      'Test spoken guidance',
                                    ),
                                    onSample:
                                        c.settings['speech_enabled'] != true ||
                                            c.settings['speech_gain_permille'] ==
                                                0 ||
                                            !(c.capabilities['tts_locales']
                                                        as List? ??
                                                    [])
                                                .any(
                                                  (tag) => '$tag'.startsWith(
                                                    c.chinese ? 'zh' : 'en',
                                                  ),
                                                )
                                        ? null
                                        : () => c.speak(
                                            c.text(
                                              '跟着提示，慢慢弹奏。准备好就开始。',
                                              'Follow the guidance and play at your own pace. Begin when you are ready.',
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            QinSectionTitle(c.text('显示', 'Display')),
                            QinPanel(
                              child: Column(
                                children: [
                                  TextSizeControl(c: c),
                                  const SizedBox(height: 8),
                                  const Divider(),
                                  const SizedBox(height: 8),
                                  SwitchListTile(
                                    secondary: const Icon(Icons.contrast),
                                    value: c.settings['high_contrast'] == true,
                                    title: Text(
                                      c.text('高对比显示', 'High contrast'),
                                    ),
                                    subtitle: Text(
                                      c.text(
                                        '增强黑白对比，突出边界。',
                                        'Use stronger black-and-white contrast and clearer boundaries.',
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (v) => c.updateSettings(
                                      values: {
                                        ...c.settings,
                                        'high_contrast': v,
                                      },
                                    ),
                                  ),
                                  SwitchListTile(
                                    secondary: const Icon(
                                      Icons.auto_awesome_outlined,
                                    ),
                                    value:
                                        c.settings['decorative_animation_enabled'] ==
                                        true,
                                    title: Text(
                                      c.text('装饰动画', 'Decorative animations'),
                                    ),
                                    subtitle: Text(
                                      c.text(
                                        '可关闭摆锤等装饰运动。',
                                        'Turn off decorative movement such as the pendulum.',
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (value) => c.updateSettings(
                                      values: {
                                        'decorative_animation_enabled': value,
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            QinSectionTitle(c.text('记录与应用', 'Records and app')),
                            QinPanel(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    c.text(
                                      '记录只保存在本机。卸载或清除应用数据后无法恢复。',
                                      'Records stay on this device. Uninstalling or clearing app data removes them.',
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  OutlinedButton.icon(
                                    onPressed:
                                        c.engine != null && !c.engine!.ended
                                        ? null
                                        : () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  RecordHealthPage(c: c),
                                            ),
                                          ),
                                    icon: const Icon(Icons.fact_check_outlined),
                                    label: Text(
                                      c.text(
                                        '记录完整性检查',
                                        'Record integrity check',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (c.hasPendingSave)
                                    Text(
                                      c.text(
                                        '请先在首页保存上次练习，再清除记录。',
                                        'Save the pending practice from Home before clearing records.',
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: context.qin.error,
                                      side: BorderSide(
                                        color: context.qin.error,
                                      ),
                                    ),
                                    onPressed:
                                        c.hasPendingSave ||
                                            c.engine != null && !c.engine!.ended
                                        ? null
                                        : () async {
                                            if (await confirm(
                                              context,
                                              c.text(
                                                '清除全部训练记录？',
                                                'Clear all practice records?',
                                              ),
                                              c.text(
                                                '练习记录、难度和教学进度会清除，语言与显示设置会保留。',
                                                'Records, difficulty and tutorial progress will be cleared. Language and display settings stay.',
                                              ),
                                              confirmLabel: c.text(
                                                '清除记录',
                                                'Clear records',
                                              ),
                                              destructive: true,
                                            )) {
                                              try {
                                                await c.clearPracticeRecords();
                                              } catch (_) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            c.text(
                                                              '暂时无法清除，请稍后重试。',
                                                              'Unable to clear records. Please retry later.',
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                }
                                              }
                                            }
                                          },
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(
                                      c.text('清除全部记录', 'Clear all records'),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AboutPage(c: c),
                                      ),
                                    ),
                                    child: Text(
                                      c.text('关于本版本', 'About this version'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class ModePicker extends StatelessWidget {
  const ModePicker({super.key, required this.c, this.descriptions = false});
  final AppController c;
  final bool descriptions;
  @override
  Widget build(BuildContext context) => RadioGroup<String>(
    groupValue: c.mode,
    onChanged: (value) => c.updateSettings(mode: value),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          RadioListTile<String>(
            value: 'ASSIST',
            selected: c.mode == 'ASSIST',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            title: Text(c.text('基础辅助', 'Gentle support')),
            subtitle: descriptions
                ? Text(c.text('短序列，更多提示', 'Short sequences and more guidance'))
                : null,
          ),
          RadioListTile<String>(
            value: 'CHALLENGE',
            selected: c.mode == 'CHALLENGE',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            title: Text(c.text('认知挑战', 'Cognitive challenge')),
            subtitle: descriptions
                ? Text(c.text('稍长的序列，逐步挑战', 'Longer sequences, at your pace'))
                : null,
          ),
        ],
      ),
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: PageTitle(c.text('关于本版本', 'About this version'))),
    body: QinPageList(
      children: [
        QinPanel(
          soft: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.piano_outlined, size: 32, color: context.qin.primary),
              const SizedBox(height: 12),
              Text(appName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                c.text('$appVersion · 内部演示版', '$appVersion · Internal demo'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        QinSectionTitle(c.text('关于练习', 'About the practice')),
        Text(
          c.text(
            '内部功能演示。包含七种练习、三节入门教学、六首钢琴曲目和三段原创旋律。提供今日推荐、本机记录与练习趋势。训练参数尚未通过专业团队评审。',
            'Internal demonstration with seven practices, three introductory lessons, six piano pieces and three original melodies. Includes daily recommendations, local records and practice trends. Practice parameters have not been professionally reviewed.',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          c.text(
            '曲目支持试听、速度记忆和演奏回顾；双区配合需通过设备双触点检查。',
            'Piano pieces support previews, remembered tempos and performance review. Two-zone practice requires a device touch check.',
          ),
        ),
        const SizedBox(height: 24),
        QinSectionTitle(c.text('音色与许可', 'Sound and licenses')),
        Text(
          c.text(
            '琴音：Salamander Grand Piano V3，Alexander Holm 录音，CC BY 3.0；已剪裁、转调并转换为移动端采样。钢琴曲目依据所提供的曲谱整理，三段练习旋律与节拍音为项目原创。',
            'Piano: Salamander Grand Piano V3 by Alexander Holm, CC BY 3.0, adapted for mobile playback. Piano pieces were transcribed from supplied scores; the three exercise melodies and metronome click are project original.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton.icon(
          onPressed: () =>
              showLicensePage(context: context, applicationName: appName),
          icon: const Icon(Icons.description_outlined),
          label: Text(c.text('音色来源与许可', 'Sound credits and licenses')),
        ),
        const SizedBox(height: 16),
        QinStatus(
          icon: Icons.lock_outline,
          text: c.text(
            '数据只保存在本机，不上传。不提供账号、导出或云端恢复。',
            'Data stays on this device without uploads, accounts, exports or cloud recovery.',
          ),
        ),
      ],
    ),
  );
}
