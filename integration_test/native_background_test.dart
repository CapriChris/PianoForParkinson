import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';

// The host runner backgrounds and restores only the isolated test package
// after the readiness markers below. No test-only native hooks are required.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Android background stops native audio and rejects note and speech requests',
    (tester) async {
      final c = AppController(
        databaseSubdirectory: 'native-background-${uuid()}',
      );
      await c.initialize();
      expect(c.error, isNull);
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
      await c.updateSettings(locale: 'en', onboard: true);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      final localVoices =
          (await c.platform.call('getCapabilities'))['tts_locales'] as List;
      final hasVoice = localVoices.any((v) => '$v'.startsWith('en'));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      for (final id in [
        'G1_MEMORY',
        'G2_INHIBITION',
        'G3_SWITCH',
        'S1_GUIDED',
        'S2_RHYTHM',
        'M1_ALTERNATE',
        'M2_DUAL_ZONE',
      ]) {
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => InstructionPage(c: c, taskId: id),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Play spoken guidance'));
        await tester.pumpAndSettle();
        if (hasVoice) {
          await tester.runAsync(() async {
            for (var i = 0; i < 30; i++) {
              if ((await c.platform.call('getAudioState'))['speech_active'] ==
                  true) {
                return;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            fail('$id speech did not start');
          });
        }
        final epoch =
            (await c.platform.call('getAudioState'))['speech_epoch'] as int;
        nav.pop();
        await tester.pumpAndSettle();
        final stopped = await c.platform.call('getAudioState');
        expect(stopped['speech_epoch'], greaterThan(epoch), reason: id);
        expect(stopped['speech_active'], false, reason: id);
        await expectLater(
          c.platform.call('speakLocal', {
            'speech_epoch': epoch,
            'locale': 'en',
            'resolved_text': 'Stale speech',
          }),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'code',
              'E_STALE_SPEECH',
            ),
          ),
        );
      }
      await tester.runAsync(() async {
        if (hasVoice) {
          await c.speak(
            List.filled(
              30,
              'This speech must stop when the app goes into the background.',
            ).join(' '),
          );
          for (var i = 0; i < 30; i++) {
            if ((await c.platform.call('getAudioState'))['speech_active'] ==
                true) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            (await c.platform.call('getAudioState'))['speech_active'],
            true,
          );
        }
        // ignore: avoid_print
        print('QINBAN_NATIVE_LOCAL_TTS_AVAILABLE=$hasVoice');
        await c.preview(0, true);
        expect(
          (await c.platform.call('getAudioState'))['active_voice_count'],
          greaterThan(0),
        );
        // ignore: avoid_print
        print('QINBAN_NATIVE_BACKGROUND_READY');
        Future<Json> waitForeground(bool foreground) async {
          for (var i = 0; i < 300; i++) {
            final state = await c.platform.call('getAudioState');
            if (state['foreground'] == foreground) return state;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          throw StateError(
            'Host did not change foreground state to $foreground',
          );
        }

        await waitForeground(false);
        // Give both the native onPause and the Dart lifecycle callback time to stop.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          (await c.platform.call('getAudioState'))['active_voice_count'],
          0,
        );
        expect(
          (await c.platform.call('getAudioState'))['speech_active'],
          false,
        );
        final backgroundError = isA<StateError>().having(
          (e) => e.message,
          'code',
          'E_AUDIO_BACKGROUND',
        );
        await expectLater(c.platform.play(0, 850), throwsA(backgroundError));
        await expectLater(
          c.platform.call('speakLocal', {
            'locale': 'en',
            'resolved_text': 'Background must be silent',
            'gain_permille': 1000,
          }),
          throwsA(backgroundError),
        );
        // ignore: avoid_print
        print('QINBAN_NATIVE_BACKGROUND_CHECKED');
        await waitForeground(true);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          (await c.platform.call('getAudioState'))['active_voice_count'],
          0,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
