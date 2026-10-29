import 'cognitive_tasks.dart';
import 'contracts.dart';

enum TrendMeasure { rate, median, p95, cv }

/// Presentation of sealed statistics only. Never rebuilds scores from events.
class TrendMetric {
  const TrendMetric({
    required this.id,
    required this.zh,
    required this.en,
    required this.source,
    this.measure = TrendMeasure.rate,
    this.lowerIsBetter = false,
    this.noteZh,
    this.noteEn,
  });

  final String id, zh, en, source;
  final TrendMeasure measure;
  final bool lowerIsBetter;
  final String? noteZh, noteEn;

  String title(bool chinese) => chinese ? zh : en;
  bool get isRate => measure == TrendMeasure.rate;
  bool get isPercent => isRate || measure == TrendMeasure.cv;
  String unit(bool chinese) => isPercent
      ? '%'
      : chinese
      ? '毫秒'
      : 'ms';
  String description(bool chinese) => [
    if (noteZh != null) chinese ? noteZh! : noteEn!,
    if (measure == TrendMeasure.p95)
      chinese
          ? 'P95 表示至少 95% 的有效样本不超过此值。'
          : 'At least 95% of valid samples are at or below P95.',
    if (measure == TrendMeasure.cv)
      chinese
          ? '每组至少 10 个有效间隔才显示；数值越低，间隔波动越小。'
          : 'At least 10 valid intervals per block; lower values mean less interval variation.'
    else if (source == 'alternate_hit_interval')
      chinese
          ? '只统计无帮助的连续命中；暂停、错键、重试和跨组会切断连续样本。间隔长短本身不代表表现好坏。'
          : 'Unassisted consecutive hits only; pauses, errors, retries and block boundaries break the run. Shorter intervals alone do not mean better performance.'
    else
      chinese
          ? (lowerIsBetter
                ? (isRate ? '数值越低，表示该类错误比例越低。' : '数值越低，表示该项误差或用时越小。')
                : '数值越高，表示该项正确比例越高。')
          : (lowerIsBetter
                ? (isRate
                      ? 'Lower values mean fewer errors of this type.'
                      : 'Lower values mean a smaller error or shorter response time.')
                : 'Higher values mean a greater proportion of correct responses.'),
  ].join(' ');

  TrendValue read(Json summary) {
    final container = summary[isRate ? 'rates' : 'timing_groups'];
    final stats = container is Map ? container[source] : null;
    if (stats is! Map) return const TrendValue(missing: true);
    if (isRate) {
      final n = stats['numerator'], d = stats['denominator'];
      if (n is! int || d is! int || d <= 0 || n < 0 || n > d) {
        return const TrendValue();
      }
      return TrendValue(number: 100.0 * n / d, numerator: n, denominator: d);
    }
    final samples = stats['samples'];
    if (samples is! int || samples <= 0) return const TrendValue();
    double? value;
    switch (measure) {
      case TrendMeasure.median:
        final n = stats['median_numerator_us'];
        final d = stats['median_denominator'];
        if (n is int && n >= 0 && d is int && d > 0) {
          value = n / d / 1000;
        }
      case TrendMeasure.p95:
        final p95 = stats['p95_us'];
        if (p95 is int && p95 >= 0) value = p95 / 1000;
      case TrendMeasure.cv:
        final cv = stats['cv_ppm'];
        if (samples >= 10 && cv is int && cv >= 0) value = cv / 10000;
      case TrendMeasure.rate:
        break;
    }
    return TrendValue(
      number: value != null && value.isFinite ? value : null,
      samples: samples,
    );
  }

  String valueLabel(TrendValue value, bool chinese) {
    if (value.number == null) {
      if (value.missing) {
        return chinese
            ? '这组未保存此指标'
            : 'This metric was not saved for this block';
      }
      if (measure == TrendMeasure.cv && (value.samples ?? 0) < 10) {
        return chinese
            ? '样本不足：每组需至少 10 个有效间隔'
            : 'Not enough samples: at least 10 intervals per block';
      }
      if (measure == TrendMeasure.cv) {
        return chinese ? '波动系数暂无有效值' : 'No valid coefficient of variation';
      }
      return chinese ? '暂无有效样本' : 'No valid samples';
    }
    final formatted = '${value.number!.toStringAsFixed(1)} ${unit(chinese)}';
    return isRate
        ? '${value.numerator} / ${value.denominator} ($formatted)'
        : '$formatted · ${chinese ? '${value.samples} 个样本' : '${value.samples} samples'}';
  }
}

class TrendValue {
  const TrendValue({
    this.number,
    this.samples,
    this.numerator,
    this.denominator,
    this.missing = false,
  });
  final double? number;
  final int? samples, numerator, denominator;
  final bool missing;
}

List<TrendMetric> trendMetrics(String taskId) => [
  TrendMetric(
    id: 'primary',
    zh: '${primaryMetricTitle(taskId, true)}率',
    en: '${primaryMetricTitle(taskId, false)} rate',
    source: 'primary',
  ),
  const TrendMetric(
    id: 'unassisted_primary',
    zh: '无帮助正确率',
    en: 'Unassisted accuracy',
    source: 'unassisted_primary',
  ),
  if (taskId == 'G1_MEMORY')
    const TrendMetric(
      id: 'position_accuracy',
      zh: '位置正确率',
      en: 'Sequence position accuracy',
      source: 'position_accuracy',
    ),
  if (taskId == 'S1_GUIDED')
    const TrendMetric(
      id: 'correct_actions',
      zh: '正确按键比例',
      en: 'Correct keypress rate',
      source: 'correct_actions',
    ),
  if (taskId == 'G2_INHIBITION') ...[
    const TrendMetric(
      id: 'no_go_correct',
      zh: '等待信号正确等待率',
      en: 'Correct wait rate',
      source: 'no_go_correct',
    ),
    const TrendMetric(
      id: 'go_omission',
      zh: '弹奏信号漏按率',
      en: 'Go omission rate',
      source: 'go_omission',
      lowerIsBetter: true,
    ),
  ],
  if (taskId == 'G3_SWITCH')
    for (final entry in const [
      ('rule_position', '规则 A 正确率', 'Rule A accuracy'),
      ('rule_shape', '规则 B 正确率', 'Rule B accuracy'),
      ('switch', '切换项正确率', 'Switch accuracy'),
      ('non_switch', '重复规则正确率', 'Repeat rule accuracy'),
    ])
      TrendMetric(id: entry.$1, zh: entry.$2, en: entry.$3, source: entry.$1),
  if (isCognitiveTask(taskId))
    for (final measure in [TrendMeasure.median, TrendMeasure.p95])
      TrendMetric(
        id: 'first_response_unassisted_${measure.name}',
        zh: '${taskId == 'G1_MEMORY' ? '首次按键用时' : '命中反应时间'}（无帮助 · ${measure == TrendMeasure.median ? '中位数' : 'P95'}）',
        en: '${taskId == 'G1_MEMORY' ? 'First keypress time' : 'Hit reaction time'} (unassisted ${measure == TrendMeasure.median ? 'median' : 'P95'})',
        source: 'first_response_unassisted',
        measure: measure,
        lowerIsBetter: true,
        noteZh: taskId == 'G1_MEMORY'
            ? '包含无帮助序列的首次按键，不限完整正确序列。'
            : '只统计无帮助的命中项。',
        noteEn: taskId == 'G1_MEMORY'
            ? 'First keypresses in unassisted sequences, including incomplete or incorrect sequences.'
            : 'Unassisted hits only.',
      ),
  if (isBeatTask(taskId)) ...[
    for (final measure in [TrendMeasure.median, TrendMeasure.p95])
      TrendMetric(
        id: 'beat_error_absolute_${measure.name}',
        zh: '绝对节拍误差（${measure == TrendMeasure.median ? '中位数' : 'P95'}）',
        en: 'Absolute beat error (${measure == TrendMeasure.median ? 'median' : 'P95'})',
        source: 'beat_error_absolute',
        measure: measure,
        lowerIsBetter: true,
        noteZh: '只统计命中项，相对计划拍点；声音输出延迟未校准。',
        noteEn: 'Hits relative to planned beats; audio output latency is not calibrated.',
      ),
    const TrendMetric(
      id: 'beat_error_absolute_unassisted_median',
      zh: '绝对节拍误差（无帮助 · 中位数）',
      en: 'Absolute beat error (unassisted median)',
      source: 'beat_error_absolute_unassisted',
      measure: TrendMeasure.median,
      lowerIsBetter: true,
      noteZh: '只统计无帮助命中项，相对计划拍点；声音输出延迟未校准。',
      noteEn: 'Unassisted hits relative to planned beats; audio output latency is not calibrated.',
    ),
  ],
  if (taskId == 'M1_ALTERNATE')
    for (final measure in [
      TrendMeasure.median,
      TrendMeasure.p95,
      TrendMeasure.cv,
    ])
      TrendMetric(
        id: 'alternate_hit_interval_${measure.name}',
        zh:
            '连续命中间隔（${switch (measure) {
              TrendMeasure.median => '中位数',
              TrendMeasure.p95 => 'P95',
              _ => '波动系数',
            }}）',
        en: 'Consecutive hit interval (${measure == TrendMeasure.median ? 'median' : measure.name.toUpperCase()})',
        source: 'alternate_hit_interval',
        measure: measure,
        noteZh: measure == TrendMeasure.cv ? '只统计无帮助的连续命中间隔。' : null,
        noteEn: measure == TrendMeasure.cv
            ? 'Unassisted consecutive hit intervals only.'
            : null,
      ),
  if (isDualTask(taskId))
    for (final measure in [TrendMeasure.median, TrendMeasure.p95])
      TrendMetric(
        id: 'dual_gap_${measure.name}',
        zh: '双区响应时间差（${measure == TrendMeasure.median ? '中位数' : 'P95'}）',
        en: 'Two-zone response gap (${measure == TrendMeasure.median ? 'median' : 'P95'})',
        source: 'dual_gap',
        measure: measure,
        lowerIsBetter: true,
        noteZh: '包含两侧唯一正确但超过容差的响应；屏幕区域不代表真实左右手。',
        noteEn: 'Includes unique correct pairs above tolerance; screen areas do not identify actual hands.',
      ),
];
