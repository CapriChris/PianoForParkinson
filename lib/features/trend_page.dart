import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_components.dart';
import '../ui/qin_theme.dart';
import '../app/page_title.dart';
import '../domain/contracts.dart';
import '../domain/history.dart';
import '../domain/cognitive_tasks.dart';
import '../domain/trend_metrics.dart';
import '../ui/metric_visuals.dart';

class TrendPage extends StatefulWidget {
  const TrendPage({super.key, required this.c, this.taskId});
  final AppController c;
  final String? taskId;
  @override
  State<TrendPage> createState() => _TrendPageState();
}

class _TrendPageState extends State<TrendPage> {
  List<Json> tasks = [], rows = [];
  List<TrendPoint> points = [];
  int taskIndex = 0, selected = 0, revision = 0;
  bool loading = true;
  bool failed = false;
  String metricId = 'primary';
  AppController get c => widget.c;
  List<TrendMetric> get metrics => trendMetrics(rows.last['task_id'] as String);
  TrendMetric get metric => metrics.firstWhere(
    (option) => option.id == metricId,
    orElse: () => metrics.first,
  );
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final request = ++revision;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final choices = await c.repository.trendTasks(taskId: widget.taskId);
      final records = choices.isEmpty
          ? <Json>[]
          : await c.repository.trendRowsForTask(
              choices.first['task_id'] as String,
            );
      final parsed = records.map(TrendPoint.fromRow).toList();
      if (!mounted || request != revision) return;
      setState(() {
        tasks = choices;
        taskIndex = 0;
        rows = records;
        points = parsed;
        metricId = 'primary';
        selected = parsed.length - 1;
        loading = false;
      });
    } catch (_) {
      if (mounted && request == revision) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Future<void> choose(int index) async {
    final request = ++revision;
    setState(() {
      taskIndex = index;
      loading = true;
      failed = false;
      points = [];
      rows = [];
    });
    try {
      final records = await c.repository.trendRowsForTask(
        tasks[index]['task_id'] as String,
      );
      final parsed = records.map(TrendPoint.fromRow).toList();
      if (!mounted || request != revision) return;
      setState(() {
        rows = records;
        points = parsed;
        if (records.isEmpty ||
            !metrics.any((option) => option.id == metricId)) {
          metricId = 'primary';
        }
        selected = parsed.length - 1;
        loading = false;
      });
    } catch (_) {
      if (mounted && request == revision) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  Future<void> showTasks() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: ListView(
          padding: qinPagePadding(context),
          children: [
            Text(
              c.text('选择练习', 'Choose practice'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < tasks.length; i++)
              Card(
                color: i == taskIndex ? context.qin.soft : context.qin.surface,
                child: ListTile(
                  title: Text(
                    taskTitle(tasks[i]['task_id'] as String, c.chinese),
                  ),
                  subtitle: Text(
                    c.text(
                      '${tasks[i]['block_count']} 组',
                      '${tasks[i]['block_count']} blocks',
                    ),
                  ),
                  trailing: i == taskIndex
                      ? Icon(Icons.check_circle, color: context.qin.primary)
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, i),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) await choose(choice);
  }

  List<String> selectedDetails() {
    final row = rows[selected];
    final summary = jsonDecode(row['result_json'] as String) as Json;
    final assistance = summary['assistance_counts'];
    final mode = row['mode'] == 'ASSIST'
        ? c.text('辅助模式', 'Assist')
        : c.text('挑战模式', 'Challenge');
    return [
      c.text('等级 ${row['level']} · $mode', 'Level ${row['level']} · $mode'),
      if (assistance is Map)
        c.text(
          '帮助 ${assistance['help'] ?? 0} · 重试 ${assistance['interrupted_retry'] ?? 0} · 暂停 ${assistance['user_pause'] ?? 0}',
          'Help ${assistance['help'] ?? 0} · Retries ${assistance['interrupted_retry'] ?? 0} · Pauses ${assistance['user_pause'] ?? 0}',
        ),
      c.text(
        '统计版本：${row['metric_version']}',
        'Metric version: ${row['metric_version']}',
      ),
    ];
  }

  Future<void> showMetrics() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: ListView(
          padding: qinPagePadding(context),
          children: [
            Text(
              c.text('选择趋势指标', 'Choose a trend metric'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final option in metrics)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  selected: option.id == metric.id,
                  title: Text(option.title(c.chinese)),
                  subtitle: Text(metricHint(option)),
                  trailing: option.id == metric.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, option.id),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) setState(() => metricId = choice);
  }

  String metricHint(TrendMetric value) {
    if (value.measure == TrendMeasure.cv) {
      return c.text(
        '至少 10 个间隔 · 越低越均匀',
        '10+ intervals · Lower means more even',
      );
    }
    if (value.source == 'alternate_hit_interval') {
      return c.text(
        '无帮助的连续命中 · 间隔不代表好坏',
        'Consecutive unassisted hits · No better/worse direction',
      );
    }
    if (value.measure == TrendMeasure.p95) {
      return c.text('95% 样本不超过此值', '95% of samples at or below this value');
    }
    return value.lowerIsBetter
        ? c.text(
            value.isRate ? '越低，该类错误越少' : '越低，用时或误差越小',
            value.isRate
                ? 'Lower means fewer errors'
                : 'Lower means less time or error',
          )
        : c.text('越高，正确比例越高', 'Higher means more correct responses');
  }

  Widget trendChoiceButton({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) => OutlinedButton(
    key: key,
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(label, textAlign: TextAlign.center)),
        const SizedBox(width: 4),
        const QinCircleArrow(radius: 12),
      ],
    ),
  );

  Widget selectedMetric() {
    final point = points[selected], value = metric.read(point.summary);
    final latest = selected == points.length - 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: context.qin.surface)),
          if (!context.qin.highContrast)
            Positioned.fill(
              child: Image.asset(
                'assets/ui_images/31-trend-jasmine-clear.webp',
                fit: BoxFit.cover,
                alignment: Alignment.bottomRight,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (!context.qin.highContrast)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xfffffefa),
                      Color(0xf7fffefa),
                      Color(0x50fffefa),
                    ],
                    stops: [0, .58, 1],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latest
                      ? c.text('最近一次', 'Latest practice')
                      : recordDateLabel(point.date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      value.number == null
                          ? '—'
                          : '${value.number!.toStringAsFixed(1)}${metric.unit(c.chinese)}',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: context.qin.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (metric.isRate &&
                        value.numerator != null &&
                        value.denominator != null)
                      Text(
                        '${value.numerator} / ${value.denominator}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value.number == null
                      ? metric.valueLabel(value, c.chinese)
                      : metricHint(metric),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: PageTitle(c.text('练习趋势', 'Practice trends'))),
    body: SafeArea(
      child: loading
          ? QinPageList(
              children: [
                QinStatus(
                  text: c.text('读取记录中…', 'Loading records…'),
                  child: const LinearProgressIndicator(),
                ),
              ],
            )
          : QinPageList(
              children: [
                if (failed)
                  QinStatus(
                    tone: QinTone.error,
                    text: c.text('记录暂时无法读取', 'Unable to read records'),
                    child: OutlinedButton(
                      onPressed: tasks.isEmpty ? load : () => choose(taskIndex),
                      child: Text(c.text('重试', 'Retry')),
                    ),
                  )
                else if (tasks.isEmpty || points.isEmpty)
                  QinEmptyState(
                    icon: Icons.show_chart,
                    title: c.text('还没有练习趋势', 'No practice trends yet'),
                    message: c.text(
                      '完成练习后，趋势会显示在这里。',
                      'Complete a practice to see your trend.',
                    ),
                  )
                else ...[
                  QinActionRow(
                    minItemWidth: 150,
                    children: [
                      trendChoiceButton(
                        icon: Icons.tune,
                        label: c.text('选择练习', 'Choose practice'),
                        onPressed: showTasks,
                      ),
                      trendChoiceButton(
                        key: const ValueKey('choose-trend-metric'),
                        icon: Icons.insights,
                        label: c.text('切换指标', 'Choose metric'),
                        onPressed: showMetrics,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.qin.soft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.text('当前练习', 'Current practice'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              taskTitle(
                                rows.last['task_id'] as String,
                                c.chinese,
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.text('当前指标', 'Current metric'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              metric.title(c.chinese),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  selectedMetric(),
                  const SizedBox(height: 12),
                  QinPanel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            Text(
                              c.text(
                                '最近 ${points.length} 组',
                                'Latest ${points.length} blocks',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              c.text(
                                '有效 ${points.where((p) => metric.read(p.summary).number != null).length} 组',
                                '${points.where((p) => metric.read(p.summary).number != null).length} valid',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TrendChart(
                          points: points,
                          selected: selected,
                          metric: metric,
                          chinese: c.chinese,
                          onSelected: (i) => setState(() => selected = i),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${points.first.date.month}/${points.first.date.day}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '${points.last.date.month}/${points.last.date.day}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        if (points
                                .where(
                                  (p) => metric.read(p.summary).number != null,
                                )
                                .length <
                            3)
                          MetricNote(
                            c.text(
                              '满 3 组有效值后连线',
                              'A line appears with 3 valid blocks',
                            ),
                          ),
                        if (points.any(
                          (p) => metric.read(p.summary).number == null,
                        ))
                          MetricNote(
                            c.text(
                              '空心标记为缺失值，不记为 0',
                              'Hollow markers are missing values, not zero',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: c.text('上一组', 'Previous block'),
                        onPressed: selected > 0
                            ? () => setState(() => selected--)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              c.text(
                                '第 ${selected + 1} / ${points.length} 组',
                                'Block ${selected + 1} / ${points.length}',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              recordDateLabel(points[selected].date),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: c.text('下一组', 'Next block'),
                        onPressed: selected < points.length - 1
                            ? () => setState(() => selected++)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  MetricNote(
                    c.text(
                      '不同难度、辅助和统计版本可能影响比较',
                      'Difficulty, assistance and metric versions may differ',
                    ),
                    icon: Icons.filter_alt_outlined,
                  ),
                  ExpansionTile(
                    title: Text(c.text('逐组数据', 'All block values')),
                    children: [
                      for (var i = 0; i < points.length; i++)
                        ListTile(
                          selected: selected == i,
                          leading: Icon(
                            selected == i
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(
                            '${i + 1} · ${recordDateLabel(points[i].date)}',
                          ),
                          subtitle: Text(
                            metric.valueLabel(
                              metric.read(points[i].summary),
                              c.chinese,
                            ),
                          ),
                          onTap: () => setState(() => selected = i),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(c.text('本组条件与统计', 'Selected block details')),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      for (final line in selectedDetails())
                        MetricNote(line, icon: Icons.tune),
                      if (metric.noteZh != null)
                        MetricNote(c.text(metric.noteZh!, metric.noteEn!)),
                      MetricNote(
                        c.text(
                          '缺失值留空，不参与连线',
                          'Missing values stay empty and break lines',
                        ),
                      ),
                    ],
                  ),
                  MetricNote(
                    c.text(
                      '训练表现趋势，不代表症状或康复变化',
                      'Practice trends, not symptom or recovery changes',
                    ),
                  ),
                ],
              ],
            ),
    ),
  );
}

class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.selected,
    this.metric = const TrendMetric(
      id: 'primary',
      zh: '正确率',
      en: 'Accuracy',
      source: 'primary',
    ),
    this.chinese = true,
    this.onSelected,
  });
  final List<TrendPoint> points;
  final int selected;
  final TrendMetric metric;
  final bool chinese;
  final ValueChanged<int>? onSelected;
  List<double?> get values => [
    for (final point in points) metric.read(point.summary).number,
  ];
  bool get connectsPoints => values.whereType<double>().length >= 3;
  String axisLabel(double value) => value >= 10000
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  @override
  Widget build(BuildContext context) {
    final data = values;
    final valid = data.whereType<double>().toList();
    final largest = valid.fold<double>(0, (a, b) => a > b ? a : b);
    final maximum = metric.isRate
        ? 100.0
        : largest > 0
        ? (largest * 1.1).ceilToDouble()
        : 1.0;
    return ExcludeSemantics(
      child: Row(
        children: [
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(80).clamp(80, 160),
            height: 180,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${axisLabel(maximum)} ${metric.unit(chinese)}',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      color: context.qin.muted,
                    ),
                  ),
                  Text(
                    '0 ${metric.unit(chinese)}',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      color: context.qin.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 180,
              child: LayoutBuilder(
                builder: (context, bounds) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: onSelected == null || points.isEmpty
                      ? null
                      : (event) {
                          final index = points.length == 1
                              ? 0
                              : ((event.localPosition.dx - 8) /
                                        math.max(1, bounds.maxWidth - 16) *
                                        (points.length - 1))
                                    .round()
                                    .clamp(0, points.length - 1);
                          onSelected!(index);
                        },
                  child: CustomPaint(
                    painter: _TrendPainter(
                      data,
                      selected,
                      Theme.of(context).colorScheme.primary,
                      context.qin.line,
                      connectsPoints,
                      maximum,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(
    this.values,
    this.selected,
    this.color,
    this.outline,
    this.connect,
    this.maximum,
  );
  final List<double?> values;
  final int selected;
  final Color color, outline;
  final bool connect;
  final double maximum;
  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(8, 8, size.width - 8, size.height - 8);
    final grid = Paint()
      ..color = outline
      ..strokeWidth = 1;
    for (final fraction in [0.0, .5, 1.0]) {
      final y = area.bottom - fraction * area.height;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
    }
    final dots = <Offset?>[
      for (var i = 0; i < values.length; i++)
        values[i] == null
            ? null
            : Offset(
                values.length == 1
                    ? area.center.dx
                    : area.left + area.width * i / (values.length - 1),
                area.bottom -
                    (values[i]! / maximum).clamp(0.0, 1.0) * area.height,
              ),
    ];
    final pen = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    if (connect) {
      for (var i = 1; i < dots.length; i++) {
        if (dots[i - 1] != null && dots[i] != null) {
          canvas.drawLine(dots[i - 1]!, dots[i]!, pen);
        }
      }
    }
    for (var i = 0; i < dots.length; i++) {
      if (dots[i] != null) {
        if (i == selected) {
          canvas.drawLine(
            Offset(dots[i]!.dx, area.top),
            Offset(dots[i]!.dx, area.bottom),
            Paint()
              ..color = outline
              ..strokeWidth = 2,
          );
          canvas.drawCircle(
            dots[i]!,
            11,
            Paint()..color = color.withValues(alpha: .15),
          );
        }
        canvas.drawCircle(dots[i]!, i == selected ? 7 : 4, pen);
      } else {
        final x = values.length == 1
            ? area.center.dx
            : area.left + area.width * i / (values.length - 1);
        canvas.drawCircle(
          Offset(x, area.bottom + 3),
          i == selected ? 6 : 4,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.color != color ||
      old.outline != outline ||
      old.connect != connect ||
      old.maximum != maximum;
}
