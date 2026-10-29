import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/switch_tutorial_page.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';

import '../domain/task_engine_test.dart' show ready;

class InterruptController extends AppController {
  InterruptController({super.clock});
  @override
  Future<void> flush() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  Completer<Map<String, dynamic>>? pendingPlay;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            calls.add(call);
            if (call.method == 'playNote' && pendingPlay != null) {
              return pendingPlay!.future;
            }
            return {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': {'voice_id': 91},
            };
          },
        );
  });
  AppController controller(ManualClock clock) {
    final c = InterruptController(clock: clock)
      ..initialized = true
      ..audioReady = true;
    c.repository.profile = {
      'locale': 'en',
      'mode': 'ASSIST',
      'settings_json': jsonEncode({
        'sound_enabled': true,
        'gain_permille': 850,
        'speech_enabled': true,
        'speech_gain_permille': 1000,
      }),
    };
    return c;
  }

  final config = PracticeConfig(
    jsonDecode(File('assets/config/demo.json').readAsStringSync()) as Json,
  );
  for (final taskId in [
    'G1_MEMORY',
    'G2_INHIBITION',
    'G3_SWITCH',
    'S1_GUIDED',
    'S2_RHYTHM',
    'M1_ALTERNATE',
  ]) {
    for (final reason in ['AUDIO_FOCUS_LOST', 'INTERRUPTED_BACKGROUND']) {
      testWidgets(
        '$taskId $reason stops audio and speech without scoring or automatic resume',
        (tester) async {
          final clock = ManualClock(), c = controller(ManualClock());
          final task = TaskEngine(
            config: config,
            clock: clock,
            taskId: taskId,
            mode: 'ASSIST',
            level: 1,
            song: [0, 1, 2, 1, 0, 1, 2, 0],
            seed: 47,
          );
          ready(task, clock);
          task.audio.clear();
          c.content.config = config;
          c.engine = task;
          final scored = task.attempts
              .where((a) => a['validity'] == 'VALID')
              .length;
          if (reason == 'INTERRUPTED_BACKGROUND') {
            c.didChangeAppLifecycleState(AppLifecycleState.paused);
          } else {
            c.interruptPlayback(reason);
          }
          await tester.pumpAndSettle();
          expect(task.phase, 'paused');
          expect(task.pauseReason, reason);
          expect(calls.any((c) => c.method == 'allNotesOff'), true);
          expect(calls.any((c) => c.method == 'stopSpeech'), true);
          expect(
            task.attempts.where((a) => a['validity'] == 'VALID').length,
            scored,
          );
          final plays = calls.where((c) => c.method == 'playNote').length;
          clock.now += 20000000;
          c.didChangeAppLifecycleState(AppLifecycleState.resumed);
          task.tick();
          await tester.pump(const Duration(seconds: 2));
          expect(task.phase, 'paused');
          expect(calls.where((c) => c.method == 'playNote').length, plays);
          c.dispose();
        },
      );
    }
  }
  testWidgets(
    'background blocks sandbox and speech, late voice replies are stopped',
    (tester) async {
      final c = controller(ManualClock());
      pendingPlay = Completer<Map<String, dynamic>>();
      final first = c.preview(0, true, pointer: 3);
      await tester.pump();
      final request = (calls.last.arguments as Map)['request_id'];
      c.didChangeAppLifecycleState(AppLifecycleState.paused);
      pendingPlay!.complete({
        'ok': true,
        'request_id': request,
        'data': {'voice_id': 100},
      });
      await first;
      await tester.pumpAndSettle();
      expect(
        calls.any(
          (call) =>
              call.method == 'stopVoice' &&
              (call.arguments as Map)['voice_id'] == 100,
        ),
        true,
      );
      final length = calls.length;
      await c.preview(1, true);
      await c.speak('background');
      expect(calls.length, length);
      pendingPlay = null;
      c.dispose();
    },
  );

  for (final surface in ['onboarding', 'preview', 'switch tutorial']) {
    testWidgets(
      '$surface releases held keys and never restarts sound on foreground return',
      (tester) async {
        final c = controller(ManualClock());
        await tester.pumpWidget(
          MaterialApp(
            home: surface == 'onboarding'
                ? Onboarding(c: c)
                : surface == 'preview'
                ? Scaffold(body: PreviewSheet(c: c))
                : SwitchTutorialPage(c: c),
          ),
        );
        await tester.pumpAndSettle();
        if (surface == 'onboarding') {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.byType(PianoKeyboard));
        final held = await tester.startGesture(
          tester.getCenter(find.byType(PianoKeyboard)),
        );
        await tester.pump();
        expect(calls.where((call) => call.method == 'playNote'), isNotEmpty);
        c.interruptPlayback('AUDIO_FOCUS_LOST');
        c.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        await held.up();
        final playCount = calls
            .where((call) => call.method == 'playNote')
            .length;
        c.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call.method == 'playNote').length,
          playCount,
        );
        if (surface == 'switch tutorial') {
          expect(find.text('That matches. You can continue.'), findsNothing);
        }
        await tester.tap(find.byType(PianoKeyboard));
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call.method == 'playNote').length,
          greaterThan(playCount),
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
