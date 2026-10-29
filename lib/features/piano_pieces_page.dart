import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/page_title.dart';
import '../domain/piano_piece.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import 'piece_sheet_preview.dart';
import 'piano_performance_page.dart';

class PianoPiecesPage extends StatelessWidget {
  const PianoPiecesPage({super.key, required this.c});
  final AppController c;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: PageTitle(c.text('钢琴曲目', 'Piano pieces'))),
    body: QinPageList(
      children: [
        QinSectionTitle(c.text('选择想弹的曲目', 'Choose a piece')),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 340 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3 &&
                    !context.qin.highContrast
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final piece in c.content.pieces)
                  SizedBox(
                    width: width,
                    child: columns == 1
                        ? QinEntryCard(
                            icon: Icons.piano_outlined,
                            title: piece.title(c.locale),
                            subtitle: piece.composer(c.locale),
                            leadingVisual: QinPieceArtwork(id: piece.id),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    PianoPiecePage(c: c, piece: piece),
                              ),
                            ),
                          )
                        : Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      PianoPiecePage(c: c, piece: piece),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  QinArtwork(
                                    asset:
                                        qinPieceImage(piece.id) ??
                                        '13-open-score.png',
                                    height: 140,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          piece.title(c.locale),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          piece.composer(c.locale),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
              ],
            );
          },
        ),
        if (c.content.pieces.isEmpty)
          Text(c.text('暂无可选曲目。', 'No pieces available.')),
      ],
    ),
  );
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
  AppController get c => widget.c;
  late int tempo = c.pieceTempo(widget.piece.id, widget.piece.tempo);
  final previewKey = GlobalKey<PieceSheetPreviewState>();
  bool busy = false;

  Future<void> rememberTempo(int value) async {
    try {
      await c.savePieceTempo(widget.piece.id, value);
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
      tempo = c.pieceTempo(widget.piece.id, widget.piece.tempo);
    }
  }

  String pieceIntroduction() {
    final id = widget.piece.id;
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

  Widget pieceIntroductionCard() => LayoutBuilder(
    builder: (context, constraints) {
      final showImage = !context.qin.highContrast;
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.5;
      final size = (constraints.maxWidth * .37).clamp(90.0, 170.0);
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.piece.title(c.locale),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            widget.piece.composer(c.locale),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            pieceIntroduction(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
      if (!showImage) return copy;
      final artwork = QinPieceArtwork(id: widget.piece.id, size: size);
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [artwork, const SizedBox(height: 12), copy],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          artwork,
          const SizedBox(width: 16),
          Expanded(child: copy),
        ],
      );
    },
  );

  Future<void> perform() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await previewKey.currentState?.stop();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PianoPerformancePage(c: c, piece: widget.piece, tempo: tempo),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && (c.audioReady || !c.soundEnabled);
    return Scaffold(
      appBar: AppBar(title: PageTitle(c.text('准备弹奏', 'Prepare to play'))),
      body: QinActionPage(
        actions: [
          FilledButton.icon(
            key: const ValueKey('enter-performance'),
            onPressed: enabled ? perform : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(c.text('进入弹奏', 'Start playing')),
          ),
        ],
        children: [
          pieceIntroductionCard(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),
          QinSectionTitle(c.text('选择弹奏速度', 'Choose your tempo')),
          Row(
            children: [
              Flexible(
                flex: 4,
                child: Text(
                  c.text('$tempo 拍/分钟', '$tempo BPM'),
                  key: const ValueKey('piece-tempo-label'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 60,
                  child: Center(
                    child: Slider(
                      key: const ValueKey('piece-tempo'),
                      value: tempo.toDouble(),
                      min: 40,
                      max: 80,
                      divisions: 4,
                      label: c.text('$tempo 拍/分钟', '$tempo BPM'),
                      semanticFormatterCallback: (value) => c.text(
                        '${value.round()} 拍/分钟',
                        '${value.round()} BPM',
                      ),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => tempo = value.round()),
                      onChangeEnd: busy
                          ? null
                          : (value) => rememberTempo(value.round()),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PieceSheetPreview(
            key: previewKey,
            c: c,
            piece: widget.piece,
            tempo: tempo,
          ),
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
    );
  }
}
