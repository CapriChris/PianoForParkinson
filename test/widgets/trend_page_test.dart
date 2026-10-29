import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/trend_page.dart';

import '../domain/history_test.dart' show sealedRow;

class _Records extends PracticeRepository {
  final Json condition = {
    'comparison_key': 'condition',
    'task_id': 'G1_MEMORY',
    'level': 1,
    'mode': 'ASSIST',
    'session_locale': 'zh-Hans',
    'block_count': 3,
    'parameters_json': canonical({
      'layout_snapshot': {'layout_id': 'PHONE_7'},
      'sequence_length': 2,
    }),
    'environment_json': canonical({
      'device_model': 'Medium Phone',
      'sound_enabled': false,
      'audio_route_category': 'MUTED',
      'app_gain_permille': 600,
    }),
    'result_json': canonical({
      'assistance_counts': {
        'user_pause': 0,
        'help': 0,
        'policy_hint': 0,
        'interrupted_retry': 0,
        'assisted_trials': 0,
      },
    }),
  };
  @override
  Future<List<Json>> trendTasks({String? taskId}) async => [
    {'task_id': 'G1_MEMORY', 'block_count': 3},
    {'task_id': 'G3_SWITCH', 'block_count': 2},
  ];
  @override
  Future<List<Json>> trendRowsForTask(String taskId) async =>
      List.generate(taskId == 'G1_MEMORY' ? 3 : 2, (i) {
        final row = sealedRow(numerator: i);
        final summary = jsonDecode(row['result_json'] as String) as Json;
        summary['comparison_key'] = 'condition-$i';
        return {
          ...condition,
          ...row,
          'task_id': taskId,
          'comparison_key': 'condition-$i',
          'result_json': canonical(summary),
          'parameter_profile_version': 'demo',
          'ended_utc_ms': i * 1000,
        };
      });
}

void main() {
  for (final size in [const Size(360, 640), const Size(800, 360)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('trend page and chooser ${size.width} $locale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('piano_training/platform/v1'),
                (call) async => {
                  'ok': true,
                  'request_id': (call.arguments as Map)['request_id'],
                  'data': <String, dynamic>{},
                },
              );
          final repo = _Records()
            ..profile = {
              'locale': locale,
              'mode': 'ASSIST',
              'onboarding_completed': 1,
              'settings_json': jsonEncode({
                'high_contrast': false,
                'sound_enabled': false,
                'gain_permille': 600,
              }),
            };
          final c = AppController(repository: repo)..initialized = true;
          await tester.pumpWidget(PianoApp(controller: c));
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .push(MaterialPageRoute<void>(builder: (_) => TrendPage(c: c)));
          await tester.pumpAndSettle();
          final scroll = find
              .descendant(
                of: find.byType(TrendPage),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.byType(TrendChart),
            140,
            scrollable: scroll,
          );
          expect(tester.takeException(), isNull);
          final choose = find.text(locale == 'en' ? 'Choose practice' : '选择练习');
          await tester.scrollUntilVisible(choose, -140, scrollable: scroll);
          await Scrollable.ensureVisible(tester.element(choose), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(choose);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final choice = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.textContaining(
              locale == 'en' ? 'Melody memory' : '旋律记忆',
            ),
          );
          await tester.scrollUntilVisible(
            choice,
            120,
            scrollable: find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await Scrollable.ensureVisible(tester.element(choice), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(choice);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TrendChart),
            140,
            scrollable: scroll,
          );
          expect(
            tester.widget<TrendChart>(find.byType(TrendChart)).points,
            hasLength(3),
          );
          await tester.scrollUntilVisible(choose, -140, scrollable: scroll);
          await Scrollable.ensureVisible(tester.element(choose), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(choose);
          await tester.pumpAndSettle();
          final other = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(
              locale == 'en' ? 'Position and shape' : '位置与图形',
            ),
          );
          await tester.scrollUntilVisible(
            other,
            120,
            scrollable: find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await Scrollable.ensureVisible(tester.element(other), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(other);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TrendChart),
            140,
            scrollable: scroll,
          );
          expect(
            tester.widget<TrendChart>(find.byType(TrendChart)).points,
            hasLength(2),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          await tester.pump();
        });
      }
    }
  }
}
