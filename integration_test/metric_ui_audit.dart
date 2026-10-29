// Synthetic UI examples. Build and launch ONLY under the isolated package ID.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/history.dart';
import 'package:piano_practice/domain/practice_metrics.dart';
import 'package:piano_practice/features/piece_result_page.dart';
import 'package:piano_practice/features/trend_page.dart';
import 'package:piano_practice/ui/metric_visuals.dart';
import 'package:piano_practice/ui/qin_theme.dart';

Json summary() {
  final s = PracticeMetrics.build(
    taskId: 'M1_ALTERNATE',
    version: 'metrics-2.1.0',
    attempts: [],
    trials: [],
    events: [],
    planned: 20,
    complete: true,
    comparisonKey: 'synthetic-ui-only',
  );
  s['completed'] = 20;
  s['active_duration_us'] = 38000000;
  final rates = s['rates'] as Json;
  rates['primary'] = {'numerator': 16, 'denominator': 20};
  rates['unassisted_primary'] = {'numerator': 15, 'denominator': 18};
  rates['assisted_primary'] = {'numerator': 1, 'denominator': 2};
  rates['beat_omission'] = {'numerator': 2, 'denominator': 20};
  rates['beat_wrong_key'] = {'numerator': 1, 'denominator': 20};
  rates['beat_extra_response'] = {'numerator': 1, 'denominator': 20};
  s['sample_counts'] = {
    'valid': 20,
    'unassisted': 18,
    'assisted': 2,
    'interrupted': 1,
    'invalid': 0,
    'response_actions': 21,
  };
  s['beat_direction_counts'] = {'early': 6, 'on_target': 2, 'late': 8};
  s['outcome_counts'] = {
    'HIT': 16,
    'OMISSION': 2,
    'WRONG_KEY': 1,
    'EXTRA_RESPONSE': 1,
    'TOO_SHORT': 0,
  };
  s['error_counts']['short_press'] = 1;
  s['error_counts']['out_of_window'] = 2;
  s['assistance_counts']['help'] = 1;
  s['assistance_counts']['assisted_trials'] = 2;
  s['assistance_counts']['user_pause'] = 1;
  final groups = s['timing_groups'] as Json;
  groups['beat_error_absolute'] = timingStatistics([
    20000,
    35000,
    40000,
    50000,
    60000,
    65000,
    70000,
    75000,
    80000,
    85000,
    90000,
    110000,
    120000,
    140000,
    155000,
    180000,
  ]);
  groups['beat_error_absolute_unassisted'] = timingStatistics([
    20000,
    35000,
    40000,
    50000,
    60000,
    65000,
    70000,
    75000,
    80000,
    85000,
    90000,
    110000,
    120000,
    140000,
    155000,
  ]);
  groups['alternate_hit_interval'] = timingStatistics(
    List.generate(12, (i) => 1250000 + i * 18000),
  );
  groups['key_hold'] = timingStatistics(
    List.generate(16, (i) => 400000 + i * 10000),
  );
  return s;
}

Json row(int i) {
  final s = summary();
  s['rates']['primary'] = {
    'numerator': [10, 12, 11, 15, 14, 16][i],
    'denominator': 20,
  };
  return {
    'session_id': 'synthetic-$i',
    'block_id': 'synthetic-block-$i',
    'task_id': 'M1_ALTERNATE',
    'level': 1,
    'mode': 'ASSIST',
    'status': 'COMPLETED',
    'session_locale': 'zh-Hans',
    'block_count': 6,
    'comparison_key': 'synthetic-ui-only',
    'metric_version': 'metrics-2.1.0',
    'parameter_profile_version': 'demo-cognitive-1.0.0',
    'started_utc_ms': 1792540800000 + i * 86400000,
    'ended_utc_ms': 1792540840000 + i * 86400000,
    'session_utc_offset_minutes': 480,
    'result_json': canonical(s),
    'environment_json': canonical({
      'device_model': 'Medium Phone',
      'sound_enabled': false,
      'audio_route_category': 'MUTED',
      'app_gain_permille': 600,
    }),
    'parameters_json': canonical({
      'bpm': 50,
      'layout_snapshot': {
        'layout_id': 'ALTERNATE_TWO_KEYS',
        'text_scale_permille': 1000,
      },
    }),
  };
}

class Examples extends PracticeRepository {
  @override
  Future<HistoryPage> historyPage({Json? after}) async =>
      HistoryPage(List.generate(6, (i) => row(5 - i)), false);
  @override
  Future<List<Json>> trendTasks({String? taskId}) async => [row(5)];
  @override
  Future<List<Json>> trendRowsForTask(String taskId) async =>
      List.generate(6, row);
}

List<Element> elements(bool Function(Widget) matches) {
  final found = <Element>[];
  void visit(Element e) {
    if (matches(e.widget)) found.add(e);
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

Future<void> showDetails() async {
  final text = elements((w) => w is Text && w.data == '详细训练表现').single;
  await Scrollable.ensureVisible(
    text,
    alignment: .2,
    duration: const Duration(milliseconds: 150),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  final box = text.findRenderObject()! as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: 987, position: point),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: 987, position: point),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<void> main() async {
  if (!const bool.fromEnvironment('ISOLATED_TEST_PACKAGE')) {
    throw StateError('Isolated package required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final uri = Uri.parse(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  final mode = uri.queryParameters['mode'] ?? 'result';
  final c = AppController(
    repository: Examples(),
    databaseSubdirectory: 'metric-ui-0143',
  );
  await c.initialize();
  if (c.error != null) throw StateError(c.error!);
  await c.updateSettings(
    locale: 'zh-Hans',
    onboard: true,
    values: {'sound_enabled': false, 'speech_enabled': false},
  );
  await c.refreshHistory();
  final p = c.content.pieces.last;
  final r = <String, dynamic>{
    'schema_version': 1,
    'session_id': 'synthetic-piece',
    'content_id': p.id,
    'content_hash': p.data['content_hash'],
    'title_zh': p.title('zh-Hans'),
    'title_en': p.title('en'),
    'tempo_bpm': 60,
    'started_utc_ms': 1792972800000,
    'ended_utc_ms': 1792972868000,
    'session_utc_offset_minutes': 480,
    'duration_us': 68000000,
    'total_ticks': p.ticks,
    'ticks_per_beat': 4,
    'total_notes': p.noteCount,
    'total_events': p.notes.length,
    'matched_notes': [
      for (var i = 0; i < p.noteCount; i++)
        if (i % 5 != 0) i,
    ],
    'wrong_presses': 3,
  };
  final home = switch (mode) {
    'piece' => PieceResultPage(c: c, record: r, alreadySaved: true),
    'history' => Scaffold(
      appBar: AppBar(title: const Text('记录')),
      body: HistoryList(c: c),
    ),
    'trend' => TrendPage(c: c),
    _ => ResultPage(c: c, record: row(5)),
  };
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: qinTheme(highContrast: false),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      home: home,
    ),
  );
  unawaited(() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mode == 'details' || mode == 'timing') {
      await showDetails();
      final target = mode == 'timing'
          ? elements((w) => w is MetricTiming && w.label == '绝对节拍误差').single
          : elements((w) => w is MetricRate && w.label == '无帮助的正确率').single;
      await Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    debugPrint(
      'METRIC_UI_READY ${jsonEncode({'mode': mode, 'synthetic': true, 'rates': elements((w) => w is MetricRateGraphic).length, 'timings': elements((w) => w is MetricTimingGraphic).length})}',
    );
  }());
}
