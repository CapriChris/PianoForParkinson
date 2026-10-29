import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart';
import '../domain/contracts.dart';
import '../domain/history.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import '../ui/metric_visuals.dart';
import 'piano_performance_page.dart';
import 'piece_review_page.dart';

class PieceResultPage extends StatefulWidget {
  const PieceResultPage({
    super.key,
    required this.c,
    required this.record,
    this.alreadySaved = false,
  });
  final AppController c;
  final Json record;
  final bool alreadySaved;
  @override
  State<PieceResultPage> createState() => _PieceResultPageState();
}

class _PieceResultPageState extends State<PieceResultPage> {
  AppController get c => widget.c;
  late bool saved = widget.alreadySaved;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    if (!saved) unawaited(save());
  }

  Future<void> save() async {
    if (saving || saved) return;
    setState(() => saving = true);
    try {
      await c.repository.savePiecePerformance(widget.record);
      if (!mounted) return;
      setState(() => saved = true);
      unawaited(c.refreshHistory());
    } catch (_) {
      // Keep the same record and ID available for an idempotent retry.
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final piece = c.content.pieceFor(r['content_id'] as String);
    final title = r[c.chinese ? 'title_zh' : 'title_en'] as String;
    final short = qinShortLandscape(context);
    final artwork = qinPieceImage(r['content_id'] as String);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!context.qin.highContrast) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.sizeOf(context).height * 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/ui_images/${(artwork ?? '08-completion-piano.png').replaceAll('.png', '.webp')}',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: context.qin.background),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xd9fffaf0),
                            Color(0xaafffaf0),
                            Color(0x22fffaf0),
                          ],
                          stops: [0, .48, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            QinActionPage(
              fixedHeader: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (short)
                    Row(
                      children: [
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.text('演奏完成', 'Performance complete'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    Text(
                      c.text('演奏完成', 'Performance complete'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (piece != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      piece.composer(c.locale),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.qin.ink),
                    ),
                  ],
                ],
              ),
              actions: [
                FilledButton.icon(
                  onPressed: !saved || piece == null
                      ? null
                      : () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PianoPerformancePage(
                                c: c,
                                piece: piece,
                                tempo: r['tempo_bpm'] as int,
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.replay),
                  label: Text(c.text('再弹一次', 'Play again')),
                ),
                OutlinedButton.icon(
                  onPressed: () => HomePage.returnHome(context, c),
                  icon: const Icon(Icons.home_outlined),
                  label: Text(c.text('返回首页', 'Home')),
                ),
              ],
              children: [
                if (!short &&
                    !context.qin.highContrast &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * .12).clamp(
                      48.0,
                      110.0,
                    ),
                  ),
                const SizedBox(height: 12),
                QinStatus(
                  backgroundOpacity: .92,
                  tone: saved
                      ? QinTone.success
                      : saving
                      ? QinTone.neutral
                      : QinTone.error,
                  text: saved
                      ? c.text('已保存记录', 'Record saved')
                      : saving
                      ? c.text('正在保存记录…', 'Saving record…')
                      : c.text(
                          '记录尚未保存，请重试。',
                          'Record not saved. Please retry.',
                        ),
                  child: saved
                      ? Text(
                          recordDateLabel(recordedDate(r, 'started_utc_ms')),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : saving
                      ? null
                      : OutlinedButton(
                          onPressed: save,
                          child: Text(c.text('重试保存', 'Retry saving')),
                        ),
                ),
                const SizedBox(height: 16),
                PieceResultMetrics(record: r, chinese: c.chinese),
                const SizedBox(height: 12),
                PieceReviewCard(
                  c: c,
                  record: r,
                  compact: true,
                  backgroundOpacity: .94,
                ),
                const SizedBox(height: 12),
                QinMetrics(
                  backgroundOpacity: .92,
                  values: [
                    QinMetric(
                      c.text('弹奏速度', 'Tempo'),
                      c.text('${r['tempo_bpm']} 拍/分钟', '${r['tempo_bpm']} BPM'),
                      icon: Icons.speed,
                    ),
                    QinMetric(
                      c.text('曲目时长', 'Piece duration'),
                      c.text(
                        '${((r['duration_us'] as int) / 1000000).toStringAsFixed(1)} 秒',
                        '${((r['duration_us'] as int) / 1000000).toStringAsFixed(1)} s',
                      ),
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PieceResultMetrics extends StatelessWidget {
  const PieceResultMetrics({
    super.key,
    required this.record,
    required this.chinese,
  });
  final Json record;
  final bool chinese;
  @override
  Widget build(BuildContext context) {
    final matched = (record['matched_notes'] as List).length;
    final total = record['total_notes'] as int;
    final valid = total > 0 && matched <= total;
    final fraction = valid ? matched / total : null;
    final ratio = valid ? '$matched / $total' : '—';
    final percent = valid
        ? '${(fraction! * 100).toStringAsFixed(1)}%'
        : (chinese ? '暂无有效样本' : 'No valid samples');
    final wrong = '${record['wrong_presses']}';
    final ring = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: MetricRingPainter(
                    fraction,
                    context.qin.primary,
                    context.qin.line,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: FittedBox(
                  child: Text(
                    ratio,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          chinese ? '匹配音符' : 'Matched notes',
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        Text(
          percent,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
    final errors = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          chinese ? '错键次数' : 'Wrong key presses',
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          wrong,
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
    return QinPanel(
      padding: const EdgeInsets.all(16),
      backgroundOpacity: .92,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.5) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                errors,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: ring),
                VerticalDivider(width: 24, color: context.qin.line),
                Expanded(child: errors),
              ],
            ),
          );
        },
      ),
    );
  }
}
