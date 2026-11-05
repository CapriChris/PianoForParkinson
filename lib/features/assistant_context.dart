import 'dart:convert';

import '../app/app_controller.dart';
import '../data/training_schedule_repository.dart';
import '../domain/cognitive_tasks.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../domain/history.dart';

enum AssistantScope { automatic, question, selected, recent }

class AssistantEvidence {
  const AssistantEvidence({
    required this.kind,
    required this.title,
    required this.date,
    required this.metrics,
    this.recordId,
    this.content,
    this.condition,
    this.startedAt,
  });

  final String kind, title, date;
  final Map<String, num> metrics;
  final String? recordId, content, condition;
  final int? startedAt;

  Json toStoredJson() => {
    'kind': kind,
    'title': title,
    'date': date,
    'metrics': metrics,
    'record_id': recordId,
    'content': content,
    'condition': condition,
    'started_at': startedAt,
  };

  factory AssistantEvidence.fromStoredJson(Json value) => AssistantEvidence(
    kind: value['kind'] as String,
    title: value['title'] as String,
    date: value['date'] as String,
    metrics: Map<String, num>.from(value['metrics'] as Map),
    recordId: value['record_id'] as String?,
    content: value['content'] as String?,
    condition: value['condition'] as String?,
    startedAt: value['started_at'] as int?,
  );

  // The local record ID and comparison key never leave the device.
  Json payload(int index) => {
    'ref': index + 1,
    'kind': kind,
    'title': title,
    'date': date,
    'metrics': metrics,
  };
}

class AssistantContext {
  const AssistantContext(this.evidence, {this.from, this.until, this.limit});
  final List<AssistantEvidence> evidence;
  final String? from, until, limit;

  Json toStoredJson() => {
    'from': from,
    'until': until,
    'limit': limit,
    'evidence': [for (final item in evidence) item.toStoredJson()],
  };

  factory AssistantContext.fromStoredJson(Json value) => AssistantContext(
    [
      for (final item in value['evidence'] as List)
        AssistantEvidence.fromStoredJson(
          Map<String, dynamic>.from(item as Map),
        ),
    ],
    from: value['from'] as String?,
    until: value['until'] as String?,
    limit: value['limit'] as String?,
  );

  Json toJson() => {
    if (from != null) 'from': from,
    if (until != null) 'until': until,
    if (limit != null) 'limit': limit,
    'evidence': [
      for (final (index, item) in evidence.indexed) item.payload(index),
    ],
  };
}

class AssistantContextReader {
  AssistantContextReader(this.c);
  final AppController c;

  static final _progressWords = RegExp(
    r'点评|复盘|回顾|表现|进步|进展|退步|怎么样|好吗|改进|比之前|练了|完成了|完成情况|练习记录|'
    r'下次.{0,6}怎么练|下一次.{0,6}怎么练|加速|提速|'
    r'how did|how am i doing|how have i|review|progress|improv|performance|'
    r'compared|practic(ed|e history)|training records|how many|记录|数据|成绩|历史|records|results|statistics',
    caseSensitive: false,
  );
  static final _practiceWords = RegExp(
    r'练习|练得|训练|练了|弹|跳|计划|这次|上次|刚才|我的|记录|数据|历史|成绩|record|result|'
    r'practice|training|session|piano|dance|my |this time|last time|today|this week',
    caseSensitive: false,
  );
  static final _howTo = RegExp(
    r'怎么(设置|打开|创建|添加|修改|删除|开启|关闭|开始)|如何(设置|打开|创建|添加|修改|删除|开启|关闭|开始)|'
    r'how (do i|to) (set|open|create|add|edit|delete|enable|disable|start)|where (is|do i)',
    caseSensitive: false,
  );
  static final _comparison = RegExp(
    r'比之前|比较|对比|进步|退步|趋势|compared|compare|trend|improv',
    caseSensitive: false,
  );
  static final _recent = RegExp(
    r'最近|近期|[这本][周月]|这个月|过去|今天|昨天|recent|lately|this week|this month|today|yesterday|\d{4}[-年]\d{1,2}[-月]\d{1,2}',
    caseSensitive: false,
  );

  AssistantScope resolve(
    AssistantScope chosen,
    String question, {
    required bool hasSelection,
    AssistantScope? previous,
  }) {
    if (chosen != AssistantScope.automatic) return chosen;
    if (_howTo.hasMatch(question)) return AssistantScope.question;
    if (_progressWords.hasMatch(question) &&
        (_practiceWords.hasMatch(question) ||
            _topic(question).task != null ||
            hasSelection ||
            previous != null && previous != AssistantScope.question)) {
      if (hasSelection && !_recent.hasMatch(question)) {
        return AssistantScope.selected;
      }
      return AssistantScope.recent;
    }
    if (RegExp(
      r'那(下次|之前|现在)|^那呢|^why\b|^what (about|next)\b|^and (then|next)\b',
      caseSensitive: false,
    ).hasMatch(question)) {
      return previous ?? AssistantScope.question;
    }
    return AssistantScope.question;
  }

  ({String? task, String? piece}) _topic(String question) {
    final lower = question.toLowerCase();
    bool includes(String term) => lower.contains(term.toLowerCase());
    for (final piece in c.content.pieces) {
      if (includes(piece.title('zh-Hans')) || includes(piece.title('en'))) {
        return (task: 'PIANO_PIECE', piece: piece.id);
      }
    }
    for (final task in exerciseIds) {
      if (includes(taskTitle(task, true)) || includes(taskTitle(task, false))) {
        return (task: task, piece: null);
      }
    }
    if (RegExp(
      r'舞蹈|平衡舞步|跳舞|dance|fandango',
      caseSensitive: false,
    ).hasMatch(question)) {
      return (task: 'DANCE', piece: null);
    }
    if (RegExp(r'曲目|piano pieces?', caseSensitive: false).hasMatch(question)) {
      return (task: 'PIANO_PIECE', piece: null);
    }
    return (task: null, piece: null);
  }

  Future<AssistantContext> read(
    String question,
    AssistantScope scope, {
    String? recordId,
    String? previousQuestion,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final topic = _topic(question);
    final previousTopic = _topic(previousQuestion ?? '');
    AssistantEvidence? selected;
    if (scope == AssistantScope.selected && recordId != null) {
      selected = await _readRecord(
        recordId,
        compare: _comparison.hasMatch(question),
      );
      if (selected == null) {
        return const AssistantContext([], limit: 'record_unavailable');
      }
      if ((topic.task != null && selected.kind != topic.task) ||
          (topic.piece != null && selected.content != topic.piece)) {
        selected = null;
      } else if (!_comparison.hasMatch(question)) {
        return AssistantContext([selected]);
      }
    }
    final requestedDate = _dateIn(question);
    final referenceDay = selected?.startedAt == null
        ? today
        : DateTime.fromMillisecondsSinceEpoch(selected!.startedAt!);
    final lower = question.toLowerCase();
    final from =
        requestedDate ??
        (lower.contains('本周') ||
                lower.contains('这周') ||
                lower.contains('this week')
            ? DateTime(today.year, today.month, today.day - today.weekday + 1)
            : lower.contains('本月') ||
                  lower.contains('这个月') ||
                  lower.contains('this month')
            ? DateTime(today.year, today.month)
            : _recent.hasMatch(question)
            ? DateTime(
                referenceDay.year,
                referenceDay.month,
                referenceDay.day - 13,
              )
            : DateTime(1970));
    final lastDate = _dateIn(question, last: true);
    final endDay = requestedDate == null
        ? referenceDay
        : lastDate != null && !lastDate.isBefore(requestedDate)
        ? lastDate
        : requestedDate;
    final until = DateTime(endDay.year, endDay.month, endDay.day + 1);
    final fromLabel = _day(from), untilLabel = _day(endDay);
    if (RegExp(r'计划|training plan', caseSensitive: false).hasMatch(question)) {
      return _plans(endDay, task: topic.task);
    }
    final task = topic.task ?? selected?.kind ?? previousTopic.task;
    final piece =
        topic.piece ??
        (selected?.kind == 'PIANO_PIECE' ? selected?.content : null) ??
        previousTopic.piece;
    final rows = await c.repository.assistantRecords(
      from: from,
      until: until,
      taskId: task,
      contentId: piece,
    );
    final candidates = <AssistantEvidence>[];
    for (final row in rows) {
      final id = row['session_id'] as String;
      if (id == selected?.recordId) continue;
      final item = await _readRecord(
        id,
        compare: task != null && _comparison.hasMatch(question),
      );
      if (item != null) candidates.add(item);
    }
    final anchor = selected ?? (candidates.isEmpty ? null : candidates.first);
    if (task != null && _comparison.hasMatch(question) && anchor != null) {
      final comparable = candidates.where(
        (item) =>
            item.recordId != anchor.recordId &&
            (item.startedAt ?? 0) <= (anchor.startedAt ?? 0) &&
            anchor.condition != null &&
            item.condition == anchor.condition,
      );
      final evidence = [anchor, ...comparable];
      return AssistantContext(
        evidence,
        from: fromLabel,
        until: untilLabel,
        limit: evidence.length < 2
            ? 'insufficient_comparable'
            : 'latest_comparable_only',
      );
    }
    if (selected == null &&
        candidates.isNotEmpty &&
        RegExp(
          r'上次|最近一次|最后一次|last (practice|training|session|time)|most recent session',
          caseSensitive: false,
        ).hasMatch(question)) {
      return AssistantContext([candidates.first]);
    }
    return AssistantContext(
      [?selected, ...candidates],
      from: fromLabel,
      until: untilLabel,
      limit: candidates.isEmpty && selected == null ? 'no_records' : null,
    );
  }

  DateTime? _dateIn(String text, {bool last = false}) {
    final matches = RegExp(r'(\d{4})[-年](\d{1,2})[-月](\d{1,2})日?')
        .allMatches(text);
    if (matches.isNotEmpty) {
      final match = last ? matches.last : matches.first;
      final year = int.parse(match[1]!);
      final month = int.parse(match[2]!);
      final day = int.parse(match[3]!);
      final date = DateTime(year, month, day);
      if (date.year == year && date.month == month && date.day == day) {
        return date;
      }
    }
    final lower = text.toLowerCase();
    final now = DateTime.now();
    if (lower.contains('昨天') || lower.contains('yesterday')) {
      return DateTime(now.year, now.month, now.day - 1);
    }
    if (lower.contains('今天') || lower.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }
    return null;
  }

  static String _day(DateTime value) => recordDateLabel(value).split(' ').first;

  Future<AssistantEvidence?> _readRecord(
    String id, {
    bool compare = false,
  }) async {
    final row = await c.repository.detail(id);
    if (row == null || row['record_unavailable'] == true) return null;
    final raw = row['result_json'];
    if (raw is! String) return null;
    final Json result;
    try {
      result = jsonDecode(raw) as Json;
    } on FormatException {
      return null;
    }
    final kind = row['task_id'] as String;
    final content = row['content_id'] as String?;
    final title = switch (kind) {
      'PIANO_PIECE' =>
        c.content.pieceFor(content)?.title(c.locale) ??
            c.text('钢琴曲目', 'Piano piece'),
      'DANCE' =>
        content == chineseDanceCourse.id
            ? c.text('新平衡舞步六式', 'Six balance steps')
            : 'Fandango',
      _ => taskTitle(kind, c.chinese),
    };
    final metrics = <String, num>{};
    String? condition;
    if (kind == 'PIANO_PIECE') {
      final matched = (result['matched_notes'] as List).length;
      final total = result['total_notes'] as int;
      final tempo = result['tempo_bpm'] as int;
      metrics.addAll({
        'matched_notes': matched,
        'total_notes': total,
        'wrong_keys': result['wrong_presses'] as int,
        'tempo_bpm': tempo,
      });
      condition = '${result['content_hash']}:$tempo';
    } else if (kind == 'DANCE') {
      final parts = result['parts'] as List? ?? [];
      metrics.addAll({
        'playback_seconds': (result['active_ms'] as int) ~/ 1000,
        'parts_reached_end': parts
            .where((p) => p is Map && p['reached_end'] == true)
            .length,
        'total_parts': parts.length,
      });
      condition = content;
    } else {
      final rate = result['rates']?['primary'];
      final valid = result['sample_counts']?['valid'];
      metrics.addAll({
        if (valid is int) 'valid_samples': valid,
        if (rate is Map && rate['numerator'] is int)
          'primary_hits': rate['numerator'] as int,
        if (rate is Map && rate['denominator'] is int)
          'primary_total': rate['denominator'] as int,
      });
      if (compare &&
          row['status'] == 'COMPLETED' &&
          (metrics['primary_total'] ?? 0) > 0) {
        final key = await c.repository.assistantExerciseCondition(id);
        if (key != null) condition = '$kind:${result['version']}:$key';
      }
    }
    void collectNumbers(Map source, String prefix) {
      for (final entry in source.entries) {
        final key = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
        final value = entry.value;
        if (value is num && value.isFinite) metrics[key] = value;
        if (value is Map) collectNumbers(value, key);
      }
    }

    if (kind != 'PIANO_PIECE' && kind != 'DANCE') {
      collectNumbers(result, 'result');
    }
    if (metrics.isEmpty) return null;
    return AssistantEvidence(
      kind: kind,
      title: title,
      date: _day(recordedDate(row, 'started_utc_ms')),
      metrics: metrics,
      recordId: id,
      content: content,
      condition: condition,
      startedAt: row['started_utc_ms'] as int,
    );
  }

  Future<AssistantContext> _plans(DateTime day, {String? task}) async {
    final repository = TrainingScheduleRepository(
      c.repository.db,
      c.repository.profile['profile_id'] as String,
    );
    final summaries = await repository.summaries(day);
    final evidence = [
      for (final row in summaries.where((row) {
        final plan = row['plan'] as Json;
        final matches = switch (task) {
          'PIANO_PIECE' => plan['kind'] == 'piece',
          'DANCE' => plan['kind'] == 'dance',
          null => true,
          _ => plan['kind'] == 'exercise' && plan['training_id'] == task,
        };
        return matches && plan['paused'] != true && planDue(plan, day);
      }))
        AssistantEvidence(
          kind: 'plan',
          title: c.text('训练计划', 'Training plan'),
          date: _day(day),
          metrics: {
            if (row['plan']['target_type'] == 'minutes') ...{
              'target_minutes': row['plan']['target'] as int,
              'playback_seconds': (row['progress'] as int) ~/ 1000,
            } else ...{
              'target_count': row['plan']['target'] as int,
              'completed_count': row['progress'] as int,
            },
          },
        ),
    ];
    return AssistantContext(
      evidence,
      limit: evidence.isEmpty ? 'no_records' : null,
    );
  }
}
