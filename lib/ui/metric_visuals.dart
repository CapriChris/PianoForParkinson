import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/cognitive_tasks.dart';
import 'qin_components.dart';
import 'qin_theme.dart';

/// Charts are projections of sealed statistics, never reconstructed scores.
class MetricRateGraphic extends StatelessWidget {
  const MetricRateGraphic({
    super.key,
    required this.label,
    required this.numerator,
    required this.denominator,
    this.chinese = true,
    this.hero = false,
    this.errorRate = false,
  });
  final String label;
  final int numerator, denominator;
  final bool chinese, hero, errorRate;
  double? get fraction =>
      denominator > 0 && numerator >= 0 && numerator <= denominator
      ? numerator / denominator
      : null;
  @override
  Widget build(BuildContext context) {
    final value = fraction;
    final color = errorRate ? context.qin.warning : context.qin.primary;
    final percentage = value == null
        ? '—'
        : '${(value * 100).toStringAsFixed(1)}%';
    final caption = value == null
        ? (chinese ? '暂无有效样本' : 'No valid samples')
        : '$numerator / $denominator';
    return Semantics(
      container: true,
      label: '$label，$percentage，$caption',
      child: ExcludeSemantics(
        child: QinPanel(
          padding: const EdgeInsets.all(16),
          soft: hero,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final ring = SizedBox.square(
                dimension: hero ? 132 : 88,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: MetricRingPainter(
                          value,
                          color,
                          context.qin.line,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          percentage,
                          style: TextStyle(
                            fontSize: hero ? 28 : 22,
                            fontWeight: FontWeight.w700,
                            color: context.qin.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
              final copy = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(caption, style: Theme.of(context).textTheme.bodySmall),
                  if (hero) ...[
                    const SizedBox(height: 8),
                    Text(
                      chinese ? '按有效样本统计' : 'Based on valid samples',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.qin.muted),
                    ),
                  ],
                ],
              );
              if (bounds.maxWidth < 270 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.5) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [ring, const SizedBox(height: 12), copy],
                );
              }
              return Row(
                children: [
                  ring,
                  const SizedBox(width: 20),
                  Expanded(child: copy),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class MetricRingPainter extends CustomPainter {
  const MetricRingPainter(this.fraction, this.color, this.track);
  final double? fraction;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawOval(rect, paint);
    if (fraction != null && fraction! > 0) {
      paint.color = color;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction!.clamp(0, 1),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MetricRingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

class MetricNote extends StatelessWidget {
  const MetricNote(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: context.qin.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

/// Paired bars share an observed scale. Neither bar is a clinical target.
class MetricTimingGraphic extends StatelessWidget {
  const MetricTimingGraphic({
    super.key,
    required this.label,
    required this.stats,
    this.chinese = true,
    this.showCv = false,
  });
  final String label;
  final Map<String, dynamic> stats;
  final bool chinese, showCv;
  @override
  Widget build(BuildContext context) {
    final samples = stats['samples'] as int? ?? 0;
    final denominator = stats['median_denominator'] as int? ?? 0;
    final median =
        samples > 0 && denominator > 0 && stats['median_numerator_us'] is num
        ? (stats['median_numerator_us'] as num) / denominator / 1000
        : null;
    final p95 = samples > 0 && stats['p95_us'] is num
        ? (stats['p95_us'] as num) / 1000
        : null;
    final maximum = math.max(median ?? 0, p95 ?? 0);
    final unit = chinese ? '毫秒' : 'ms';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: QinPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.timer_outlined, color: context.qin.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (median == null || p95 == null)
              Text(chinese ? '暂无有效样本' : 'no valid samples')
            else ...[
              MetricBar(
                label: chinese ? '中位数' : 'Median',
                value: '${median.toStringAsFixed(1)} $unit',
                fraction: maximum == 0 ? 0 : median / maximum,
              ),
              const SizedBox(height: 12),
              MetricBar(
                label: 'P95',
                value: '${p95.toStringAsFixed(1)} $unit',
                fraction: maximum == 0 ? 0 : p95 / maximum,
                secondary: true,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  Text(
                    chinese ? '$samples 个样本' : '$samples samples',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    chinese ? '95% 样本 ≤ P95' : '95% of samples ≤ P95',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    chinese ? '条长按本卡范围缩放' : 'Bars share this card’s scale',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (showCv) ...[
                const SizedBox(height: 8),
                Text(
                  samples < 10
                      ? (chinese
                            ? '波动系数需至少 10 个有效间隔'
                            : 'CV needs at least 10 valid intervals')
                      : stats['cv_ppm'] == null
                      ? (chinese ? '波动系数暂无有效值' : 'No valid CV')
                      : 'CV ${((stats['cv_ppm'] as num) / 10000).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  chinese
                      ? '波动系数越低，间隔越均匀'
                      : 'Lower CV means more even intervals',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class MetricBar extends StatelessWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.secondary = false,
  });
  final String label, value;
  final double? fraction;
  final bool secondary;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label，$value',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction?.clamp(0, 1) ?? 0,
              minHeight: secondary ? 6 : 10,
              backgroundColor: context.qin.line,
              color: secondary ? context.qin.muted : context.qin.primary,
            ),
          ),
        ],
      ),
    ),
  );
}

class MetricCountBars extends StatelessWidget {
  const MetricCountBars({super.key, required this.title, required this.counts});
  final String title;
  final Map<String, int> counts;
  @override
  Widget build(BuildContext context) {
    final maximum = counts.values.fold<int>(0, math.max);
    return QinPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          for (final entry in counts.entries) ...[
            const SizedBox(height: 14),
            MetricBar(
              label: entry.key,
              value: '${entry.value}',
              fraction: maximum == 0 ? 0 : entry.value / maximum,
            ),
          ],
        ],
      ),
    );
  }
}

class MetricNoteMap extends StatelessWidget {
  const MetricNoteMap({
    super.key,
    required this.total,
    required this.matched,
    this.chinese = true,
  });
  final int total;
  final Set<int> matched;
  final bool chinese;
  @override
  Widget build(BuildContext context) => QinPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chinese ? '逐音回顾 →' : 'Note-by-note →',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Semantics(
          label: chinese
              ? '按曲谱顺序，匹配 ${matched.length} / $total 个音符'
              : 'Score order: ${matched.length} of $total notes matched',
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, bounds) => SizedBox(
                width: bounds.maxWidth,
                height: math
                    .max(
                      54,
                      (total / math.max(1, (bounds.maxWidth / 18).floor()))
                              .ceil() *
                          18,
                    )
                    .toDouble(),
                child: CustomPaint(
                  key: const ValueKey('note-match-map'),
                  painter: _NoteMapPainter(
                    total,
                    matched,
                    context.qin.primary,
                    context.qin.line,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _MapLegend(
              icon: Icons.check_circle,
              label: chinese ? '匹配' : 'Matched',
              color: context.qin.primary,
            ),
            _MapLegend(
              icon: Icons.remove_circle_outline,
              label: chinese ? '未匹配' : 'Unmatched',
              color: context.qin.muted,
            ),
          ],
        ),
      ],
    ),
  );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
}

class _NoteMapPainter extends CustomPainter {
  _NoteMapPainter(this.total, this.matched, this.color, this.track);
  final int total;
  final Set<int> matched;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final columns = math.min(total, math.max(1, (size.width / 18).floor()));
    final rows = (total / columns).ceil();
    final cell = math.min(
      18.0,
      math.min(size.width / columns, size.height / rows),
    );
    for (var i = 0; i < total; i++) {
      final center = Offset(
        (i % columns + .5) * size.width / columns,
        (i ~/ columns + .5) * size.height / rows,
      );
      final radius = cell * .37;
      final hit = matched.contains(i);
      final pen = Paint()..color = hit ? color : track;
      canvas.drawCircle(center, radius, pen);
      pen
        ..color = (hit ? Colors.white : color)
        ..strokeWidth = math.max(1, cell * .08)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (hit) {
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - radius * .5, center.dy)
            ..lineTo(center.dx - radius * .1, center.dy + radius * .4)
            ..lineTo(center.dx + radius * .5, center.dy - radius * .4),
          pen,
        );
      } else {
        canvas.drawLine(
          center - Offset(radius * .4, 0),
          center + Offset(radius * .4, 0),
          pen,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoteMapPainter old) =>
      old.total != total ||
      old.matched != matched ||
      old.color != color ||
      old.track != track;
}

class HistoryMetricStrip extends StatelessWidget {
  const HistoryMetricStrip({
    super.key,
    required this.record,
    this.chinese = true,
  });
  final Map<String, dynamic> record;
  final bool chinese;
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? summary;
    final raw = record['result_json'];
    if (raw is String) {
      try {
        summary = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        /* Older record: keep its textual entry available. */
      }
    }
    final piece = record['task_id'] == 'PIANO_PIECE';
    final numerator = piece
        ? (summary?['matched_notes'] as List?)?.length
        : summary?['rates']?['primary']?['numerator'];
    final denominator = piece
        ? (summary?['total_notes'])
        : summary?['rates']?['primary']?['denominator'];
    final valid =
        numerator is int &&
        denominator is int &&
        denominator > 0 &&
        numerator >= 0 &&
        numerator <= denominator;
    return MetricBar(
      label: piece
          ? (chinese ? '匹配音符' : 'Matched notes')
          : primaryMetricTitle(record['task_id'] as String, chinese),
      value: valid
          ? '$numerator / $denominator · ${(numerator / denominator * 100).toStringAsFixed(1)}%'
          : (chinese ? '暂无有效样本' : 'No valid samples'),
      fraction: valid ? numerator / denominator : null,
    );
  }
}
