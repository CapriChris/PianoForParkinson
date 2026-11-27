import '../ui/spotlight_tour.dart';
import 'capture_widgets.dart';
import '../ui/qin_press.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/page_title.dart';
import '../domain/piano_piece.dart';
import '../domain/piece_timing.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import 'piece_sheet_preview.dart';
import 'piano_performance_page.dart';
import 'music_import_page.dart';

class PianoPiecesPage extends StatelessWidget {
  const PianoPiecesPage({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => c.content.pieces.isEmpty
      ? Scaffold(
          appBar: AppBar(title: Text(c.text('弹奏训练', 'Piano training'))),
          body: Center(child: Text(c.text('暂无可选曲目', 'No pieces available'))),
        )
      : PianoPiecePage(c: c, piece: c.content.pieces.first);
}

/// Preparation and audition only. The performance page has no tempo controls.
class PianoPiecePage extends StatefulWidget {
  const PianoPiecePage({super.key, required this.c, required this.piece});
  final AppController c;
  final PianoPiece piece;
  @override
  State<PianoPiecePage> createState() => _PianoPiecePageState();
}

class _PianoPiecePageState extends State<PianoPiecePage> {
  final guideSong = GlobalKey(),
      guideMode = GlobalKey(),
      guideTempo = GlobalKey(),
      guideCapture = GlobalKey(),
      guideStart = GlobalKey();
  List<SpotlightStep> get guideSteps => [
    SpotlightStep(
      target: guideSong,
      title: c.text('选择曲目', 'Choose a piece'),
      message: c.text(
        '点击箭头打开曲目抽屉，可以选曲，也可以导入 MP3。',
        'Open the song drawer to choose a piece or import an MP3.',
      ),
    ),
    SpotlightStep(
      target: guideMode,
      shape: SpotlightShape.roundedRectangle,
      borderRadius: 32,
      title: c.text('选择模式', 'Choose a mode'),
      message: c.text(
        '入门练习会等你按对后再继续；正常训练会按节奏持续播放。',
        'Beginner mode waits for the correct key. Normal mode keeps the rhythm moving.',
      ),
    ),
    SpotlightStep(
      target: guideTempo,
      shape: SpotlightShape.roundedRectangle,
      title: c.text('调整速度', 'Set the tempo'),
      message: c.text(
        '拖动滑轨调整速度，靠近整十会吸附。左右按钮每次微调一拍，初次可以从慢速开始。',
        'Drag to change tempo, with snapping near tens. The buttons adjust one BPM at a time. Start slowly.',
      ),
    ),
    SpotlightStep(
      target: previewKey,
      shape: SpotlightShape.roundedRectangle,
      title: c.text('先看一次示范', 'Watch a preview'),
      message: c.text(
        '点击播放，看提示符落到琴键，以及正确按住、松开的演示。预览琴键不用手动按。',
        'Play the preview to watch falling cues and the correct hold and release. The preview keys are automatic.',
      ),
      advanceOnTap: false,
    ),
    SpotlightStep(
      target: guideCapture,
      shape: SpotlightShape.roundedRectangle,
      prepare: () async {
        await previewKey.currentState?.stop();
      },
      title: c.text('可选面部采集', 'Optional face capture'),
      message: c.text(
        '面部采集是可选项。开启前会单独请求授权，可以保持关闭进行训练。',
        'Face capture is optional and asks for separate permission. You can practise with it switched off.',
      ),
      advanceOnTap: false,
    ),
    SpotlightStep(
      target: guideStart,
      shape: SpotlightShape.roundedRectangle,
      title: c.text('准备开始', 'Ready to practise'),
      message: c.text(
        '点击开始后确认，倒数三秒。提示符随后提前下落，准备好再跟随节奏按键。',
        'Start, confirm, and count down from three. Cues then approach the keys before the music begins.',
      ),
    ),
  ];
  AppController get c => widget.c;
  late PianoPiece piece = widget.piece;
  late int tempo = c.pieceTempo(piece.id, piece.tempo).clamp(30, piece.tempo);
  final previewKey = GlobalKey<PieceSheetPreviewState>();
  final captureKey = GlobalKey<CapturePreparationState>();
  bool busy = false;
  PiecePracticeMode practiceMode = PiecePracticeMode.continuous;

  Future<void> rememberTempo(int value) async {
    try {
      await c.savePieceTempo(piece.id, value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.text('速度未保存，请重试。', 'Tempo was not saved. Please retry.'),
            ),
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(PianoPiecePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id || oldWidget.c != widget.c) {
      piece = widget.piece;
      tempo = c.pieceTempo(piece.id, piece.tempo).clamp(30, piece.tempo);
    }
  }

  String pieceIntroduction([PianoPiece? value]) {
    final id = (value ?? piece).id;
    if (id.contains('ode-to-joy')) {
      return c.text(
        '贝多芬第九交响曲中广为传唱的主题，旋律明朗而有力。',
        'A bright, memorable theme from Beethoven’s Ninth Symphony.',
      );
    }
    if (id.contains('frere')) {
      return c.text(
        '一首旋律轻快、乐句重复的法国传统歌曲。',
        'A lively traditional French song with repeating phrases.',
      );
    }
    if (id.contains('twinkle')) {
      return c.text(
        '熟悉的星空主题旋律，乐句清晰而温柔。',
        'A familiar, gentle melody with clear phrases.',
      );
    }
    if (id.contains('saints')) {
      return c.text(
        '一首节奏鲜明、充满活力的传统歌曲。',
        'A traditional song with a lively, distinctive rhythm.',
      );
    }
    if (id.contains('birthday')) {
      return c.text(
        '熟悉的生日祝福旋律，适合在温馨时刻弹奏。',
        'A familiar birthday melody for a celebratory moment.',
      );
    }
    if (id.contains('sunshine')) {
      return c.text(
        '一首温暖亲切的歌曲，旋律柔和流畅。',
        'A warm, familiar song with a flowing melody.',
      );
    }
    return c.text('跟随旋律，以自己的节奏弹奏。', 'Follow the melody at your own pace.');
  }

  Widget songCard(
    PianoPiece value,
    VoidCallback? onTap, {
    bool selected = false,
  }) => Card(
    margin: EdgeInsets.zero,
    color: context.qin.surface,
    child: QinInkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            QinPieceArtwork(
              id: value.id,
              size: MediaQuery.sizeOf(context).width < 350 ? 68 : 88,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value.title(c.locale),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value.composer(c.locale),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    pieceIntroduction(value),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (selected)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        Icons.expand_more,
                        key: guideSong,
                        color: context.qin.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: QinPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [QinSectionTitle(title), ...children],
      ),
    ),
  );

  Future<void> choosePiece() async {
    await previewKey.currentState?.stop();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<PianoPiece>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .75,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    c.text('选择曲目', 'Choose a piece'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                QinIconButton(
                  tooltip: c.text('关闭', 'Close'),
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final option in c.content.pieces)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: songCard(
                        option,
                        () => Navigator.pop(sheetContext, option),
                      ),
                    ),
                  QinEntryCard(
                    icon: Icons.audio_file_outlined,
                    title: c.text('导入 MP3 自制曲目', 'Create a piece from MP3'),
                    subtitle: c.text(
                      '本地提取旋律，试听校对后保存',
                      'Extract, listen and review locally',
                    ),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => MusicImportPage(c: c),
                        ),
                      );
                      if (saved == true &&
                          mounted &&
                          c.content.pieces.isNotEmpty) {
                        selectPiece(c.content.pieces.last);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) selectPiece(chosen);
  }

  void selectPiece(PianoPiece value) => setState(() {
    piece = value;
    tempo = c.pieceTempo(piece.id, piece.tempo).clamp(30, piece.tempo);
  });

  void stepTempo(int delta) {
    setState(() => tempo = (tempo + delta).clamp(30, piece.tempo));
    unawaited(rememberTempo(tempo));
  }

  Future<void> perform() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await previewKey.currentState?.stop();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PianoPerformancePage(
            c: c,
            piece: piece,
            tempo: tempo,
            capture: captureKey.currentState?.claim(),
            practiceMode: practiceMode,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && (c.audioReady || !c.soundEnabled);
    return SpotlightTour(
      c: c,
      preferenceKey: 'spotlight_piano_v1',
      steps: guideSteps,
      onFinish: () async {
        await previewKey.currentState?.stop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Navigator.canPop(context) ? const QinBackButton() : null,
          title: PageTitle(c.text('弹奏训练', 'Piano training')),
        ),
        body: QinActionPage(
          actions: [
            KeyedSubtree(
              key: guideStart,
              child: QinFilledButton.icon(
                key: const ValueKey('enter-performance'),
                onPressed: enabled ? perform : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(c.text('开始训练', 'Start training')),
              ),
            ),
          ],
          children: [
            section(c.text('选择曲目', 'Choose a piece'), [
              songCard(piece, busy ? null : choosePiece, selected: true),
            ]),
            section(c.text('训练配置', 'Training settings'), [
              Text(
                c.text('训练模式', 'Practice mode'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<PiecePracticeMode>(
                key: guideMode,
                segments: [
                  ButtonSegment(
                    value: PiecePracticeMode.beginner,
                    label: Text(c.text('入门练习', 'Beginner')),
                  ),
                  ButtonSegment(
                    value: PiecePracticeMode.continuous,
                    label: Text(c.text('正常训练', 'Normal')),
                  ),
                ],
                selected: {practiceMode},
                onSelectionChanged: busy
                    ? null
                    : (value) => setState(() => practiceMode = value.single),
              ),
              const SizedBox(height: 8),
              Text(
                practiceMode == PiecePracticeMode.beginner
                    ? c.text(
                        '音符到达时等待你按对琴键，再继续前进。',
                        'Notes wait for the correct key before moving on.',
                      )
                    : c.text(
                        '音乐持续播放，跟随节奏完成弹奏。',
                        'Follow the rhythm while the music plays continuously.',
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                c.text('训练速度', 'Practice tempo'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                c.text('$tempo 拍/分钟', '$tempo BPM'),
                key: const ValueKey('piece-tempo-label'),
              ),
              Row(
                key: guideTempo,
                children: [
                  QinIconButton(
                    key: const ValueKey('tempo-minus'),
                    tooltip: c.text('减慢 1 拍/分钟', 'Decrease by 1 BPM'),
                    onPressed: busy || tempo <= 30 ? null : () => stepTempo(-1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('piece-tempo'),
                      semanticFormatterCallback: (value) => c.text(
                        '${value.round()} 拍/分钟',
                        '${value.round()} BPM',
                      ),
                      value: tempo.toDouble(),
                      min: 30,
                      max: piece.tempo.toDouble(),
                      divisions: piece.tempo > 30 ? piece.tempo - 30 : null,
                      onChanged: busy
                          ? null
                          : (value) => setState(
                              () => tempo = PieceTiming.snapTempo(
                                value,
                                piece.tempo,
                              ),
                            ),
                      onChangeEnd: busy
                          ? null
                          : (value) => rememberTempo(
                              PieceTiming.snapTempo(value, piece.tempo),
                            ),
                    ),
                  ),
                  QinIconButton(
                    key: const ValueKey('tempo-plus'),
                    tooltip: c.text('加快 1 拍/分钟', 'Increase by 1 BPM'),
                    onPressed: busy || tempo >= piece.tempo
                        ? null
                        : () => stepTempo(1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                c.text('训练预览', 'Training preview'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              PieceSheetPreview(
                key: previewKey,
                c: c,
                piece: piece,
                tempo: tempo,
                waterfall: true,
              ),
            ]),
            section(c.text('面部采集授权', 'Face capture permission'), [
              KeyedSubtree(
                key: guideCapture,
                child: CapturePreparation(key: captureKey, c: c),
              ),
            ]),
            if (!c.audioReady && c.soundEnabled) ...[
              const SizedBox(height: 16),
              Text(
                c.text(
                  '琴音尚未准备好，请返回重试。',
                  'Piano audio is not ready. Go back and retry.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
