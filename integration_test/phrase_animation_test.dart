import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/training_page.dart';

import 'rhythm_flow_test.dart' show cleanup;
import 'responsive_flow_test.dart' show backHome;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'M1 complete demo continues rendering while background snapshots save',
    (tester) async {
      final c = AppController(
        databaseSubdirectory: 'phrase-animation-${uuid()}',
      );
      await c.initialize();
      cleanup(c);
      await c.updateSettings(locale: 'en', onboard: true);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => TrainingPage(c: c, taskId: 'M1_ALTERNATE'),
            ),
          );
      await tester.pump();
      final frameTimes = <int>[], callbackGaps = <int>[];
      void timings(List<FrameTiming> frames) {
        if (c.engine?.phase == 'demo') {
          frameTimes.addAll(frames.map((v) => v.buildDuration.inMicroseconds));
        }
      }

      SchedulerBinding.instance.addTimingsCallback(timings);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(timings),
      );
      var seenDemo = false, snapshots = 0, lastFlush = -1, previous = -1;
      var previousProgress = 0.0;
      final clock = Stopwatch()..start();
      final pending = <Future<void>>[];
      for (var i = 0; i < 2200; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final e = c.engine;
        expect(c.storageError, isNull);
        expect(e?.phase, isNot('paused'));
        if (e?.phase == 'demo') {
          seenDemo = true;
          final now = clock.elapsedMicroseconds;
          if (previous >= 0) callbackGaps.add(now - previous);
          previous = now;
          expect(e!.phraseProgress, greaterThanOrEqualTo(previousProgress));
          previousProgress = e.phraseProgress;
          if (lastFlush < 0 || now - lastFlush >= 2000000) {
            lastFlush = now;
            snapshots++;
            pending.add(c.flush());
          }
        } else if (seenDemo) {
          break;
        }
      }
      await Future.wait(pending);
      expect(seenDemo, true);
      expect(snapshots, greaterThanOrEqualTo(8));
      expect(callbackGaps.length, greaterThan(200));
      final ticks = c.engine!.events
          .where(
            (v) =>
                v['kind'] == 'METRONOME_TICK' &&
                v['payload']['owner'] == 'DEMO',
          )
          .toList();
      expect(ticks, hasLength(12));
      final origin = ticks.first['payload']['scheduled_offset_us'] as int;
      for (var i = 0; i < 12; i++) {
        expect(
          ticks[i]['payload']['scheduled_offset_us'],
          origin + i * 60000000 ~/ 40,
        );
      }
      final lateness = ticks
          .map(
            (v) =>
                (v['offset_us'] - v['payload']['scheduled_offset_us']) as int,
          )
          .toList();
      callbackGaps.sort();
      frameTimes.sort();
      debugPrint(
        'PHRASE_PERFORMANCE ${jsonEncode({'snapshots': snapshots, 'rendered_demo_frames': frameTimes.length, 'frame_build_p95_us': frameTimes.isEmpty ? null : frameTimes[(frameTimes.length * .95).ceil() - 1], 'frame_build_max_us': frameTimes.isEmpty ? null : frameTimes.last, 'pump_gap_p95_us': callbackGaps[(callbackGaps.length * .95).ceil() - 1], 'pump_gap_max_us': callbackGaps.last, 'demo_beat_max_lateness_us': lateness.reduce(max)})}',
      );
      await backHome(tester, c);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
