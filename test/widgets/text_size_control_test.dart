import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';

class _MemorySettings extends PracticeRepository {
  bool fail = false;
  @override
  Future<void> settingsUpdate({
    String? locale,
    String? mode,
    Json? settings,
    bool onboard = false,
  }) async {
    if (fail) throw StateError('write failed');
    profile = {
      ...profile,
      if (settings != null) 'settings_json': canonical(settings),
    };
  }
}

void main() {
  testWidgets(
    'new text size range previews, persists and returns to system scaling',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.25;
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
      final repo = _MemorySettings()
        ..profile = {
          'locale': 'zh-Hans',
          'mode': 'ASSIST',
          'onboarding_completed': 1,
          'settings_json': jsonEncode({
            'high_contrast': false,
            'sound_enabled': false,
            'gain_permille': 0,
          }),
        };
      final c = AppController(repository: repo)..initialized = true;
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final sliderFinder = find.byKey(const ValueKey('text-size-slider'));
      final scroll = find
          .descendant(
            of: find.byType(SettingsPage),
            matching: find.byType(Scrollable),
          )
          .last;
      await tester.scrollUntilVisible(sliderFinder, 250, scrollable: scroll);
      await tester.pumpAndSettle();
      double scale() =>
          MediaQuery.textScalerOf(tester.element(find.byType(SettingsPage)))
              .scale(20);
      expect(scale(), closeTo(25, .01));
      expect(tester.widget<Slider>(sliderFinder).min, 80);
      expect(tester.widget<Slider>(sliderFinder).max, 120);
      expect(tester.widget<Slider>(sliderFinder).value, 100);
      tester.widget<Slider>(sliderFinder).onChanged!(110);
      await tester.pumpAndSettle();
      expect(scale(), closeTo(27.5, .01));
      tester.widget<Slider>(sliderFinder).onChangeEnd!(110);
      await tester.pumpAndSettle();
      expect(c.settings['text_size_percent_v3'], 110);
      expect(tester.takeException(), isNull);
      final follow = find.byKey(const ValueKey('text-size-follow-system'));
      await tester.ensureVisible(follow);
      await tester.pumpAndSettle();
      await tester.tap(follow);
      await tester.pumpAndSettle();
      expect(c.settings['text_size_percent_v3'], isNull);
      expect(scale(), closeTo(25, .01));
      await tester.ensureVisible(sliderFinder);
      await tester.pumpAndSettle();
      final sliderRect = tester.getRect(sliderFinder);
      await tester.tapAt(Offset(sliderRect.left + 38, sliderRect.center.dy));
      await tester.pumpAndSettle();
      expect(c.settings['text_size_percent_v3'], lessThan(100));
      expect(
        scale(),
        closeTo(25 * c.settings['text_size_percent_v3'] / 100, .01),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'previous values map into the new range without discarding old settings',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('piano_training/platform/v1'),
            (call) async => {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': <String, dynamic>{},
            },
          );
      final repo = _MemorySettings()
        ..profile = {
          'locale': 'zh-Hans',
          'mode': 'ASSIST',
          'onboarding_completed': 1,
          'settings_json': jsonEncode({
            'high_contrast': false,
            'sound_enabled': false,
            'gain_permille': 0,
            'text_scale_percent': 100,
          }),
        };
      final c = AppController(repository: repo)..initialized = true;
      expect(c.textScalePercent, 100);
      repo.profile['settings_json'] = canonical({
        ...c.settings,
        'text_size_percent_v2': 110,
      });
      expect(c.textScalePercent, 100);
      await c.saveTextScale(null);
      expect(c.textScalePercent, isNull);
      expect(c.settings['text_scale_percent'], 100);
      c.dispose();
      await tester.pump();
    },
  );

  testWidgets('failed text size save restores the previous choice', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async => {
            'ok': true,
            'request_id': (call.arguments as Map)['request_id'],
            'data': <String, dynamic>{},
          },
        );
    final repo = _MemorySettings()
      ..profile = {
        'locale': 'zh-Hans',
        'mode': 'ASSIST',
        'onboarding_completed': 1,
        'settings_json': jsonEncode({
          'high_contrast': false,
          'sound_enabled': false,
          'gain_permille': 0,
          'text_scale_percent': 120,
        }),
      };
    final c = AppController(repository: repo)..initialized = true;
    c.previewTextScale(90);
    expect(c.textScalePercent, 90);
    repo.fail = true;
    await expectLater(c.saveTextScale(90), throwsStateError);
    expect(c.textScalePercent, 120);
    c.dispose();
    await tester.pump();
  });
}
