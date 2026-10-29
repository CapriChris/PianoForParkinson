import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/keyboard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'six tasks: native voices stop, interrupted attempts persist and foreground return stays paused',
    (tester) async {
      final clock = ManualClock();
      final c = AppController(
        clock: clock,
        databaseSubdirectory: 'interruptions-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
      await c.updateSettings(locale: 'en', onboard: true);
      final root = c.capabilities['storage_path'] as String;
      final path = '$root/${c.databaseSubdirectory}';
      addTearDown(() async {
        c.dispose();
        if (c.repository.db.isOpen) await c.repository.db.close();
        final directory = Directory(path).absolute;
        if (!directory.path.startsWith(
              '${Directory(root).absolute.path}${Platform.pathSeparator}',
            ) ||
            !directory.path.endsWith(c.databaseSubdirectory!)) {
          throw StateError('Invalid isolated cleanup path');
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      Json? layout;
      for (final taskId in [
        'G1_MEMORY',
        'G2_INHIBITION',
        'G3_SWITCH',
        'S1_GUIDED',
        'S2_RHYTHM',
        'M1_ALTERNATE',
      ]) {
        for (final reason in ['AUDIO_FOCUS_LOST', 'INTERRUPTED_BACKGROUND']) {
          layout = null;
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              home: Scaffold(
                body: SizedBox(
                  height: 144,
                  child: PianoKeyboard(
                    count: taskId == 'M1_ALTERNATE' ? 2 : 7,
                    active: const {0, 1, 2, 3, 4, 5, 6},
                    onDown: (p, k, d, xy) {},
                    onUp: (p, k, cancel, xy) {},
                    onLayout: (snapshot) => layout = snapshot,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await c.start(taskId, layout!);
          final task = c.engine!;
          // Advance the real engine with an injected clock; native audio below
          // still uses SoundPool. This is not a physical timing measurement.
          for (var tick = 0; tick < 2500 && task.phase != 'response'; tick++) {
            clock.now += 20000;
            task.tick();
            if (task.phase == 'cue') task.cuePresented();
          }
          expect(task.phase, 'response');
          task.audio.clear();
          // Start a real native voice independently of correctness of the target.
          await c.preview(0, true, pointer: -300);
          expect(
            (await c.platform.call('getAudioState'))['active_voice_count'],
            greaterThan(0),
          );
          final validBefore = task.attempts
              .where((a) => a['validity'] == 'VALID')
              .length;
          if (reason == 'INTERRUPTED_BACKGROUND') {
            c.didChangeAppLifecycleState(AppLifecycleState.paused);
          } else {
            c.interruptPlayback(reason);
          }
          await c.stopAllPlayback();
          await c.flush();
          expect(c.storageError, isNull);
          expect(task.phase, 'paused');
          expect(
            (await c.platform.call('getAudioState'))['active_voice_count'],
            0,
          );
          expect(
            task.attempts.where((a) => a['validity'] == 'VALID').length,
            validBefore,
          );
          c.didChangeAppLifecycleState(AppLifecycleState.resumed);
          clock.now += 2000000;
          await tester.pump(const Duration(milliseconds: 100));
          expect(task.phase, 'paused');
          expect(
            (await c.platform.call('getAudioState'))['active_voice_count'],
            0,
          );
          await c.exit();
          expect(c.saved, true);
          final attempts = await c.repository.db.query(
            'attempts',
            where: 'session_id=?',
            whereArgs: [task.id],
          );
          expect(attempts.where((a) => a['validity'] == 'VALID'), isEmpty);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
