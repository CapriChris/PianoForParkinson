// Manual emulator audio audit: launch only with the isolated application ID.
// Uses the production preview widget and audio backends, not fake playback.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/piece_result_page.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/ui/qin_theme.dart';

class AuditController extends AppController {
  AuditController() : super(databaseSubdirectory: 'audio-audit-0139');
  @override
  Future<void> preview(
    int key,
    bool down, {
    int? pointer,
    int ratePermille = 1000,
  }) async {
    final requested = clock.now;
    await super.preview(
      key,
      down,
      pointer: pointer,
      ratePermille: ratePermille,
    );
    debugPrint(
      'AUDIO_AUDIT_NOTE ${jsonEncode({'requested_us': requested, 'ack_us': clock.now, 'sample': key, 'down': down, 'rate_permille': ratePermille})}',
    );
  }
}

T? findWidget<T extends Widget>({Key? key}) {
  T? found;
  void visit(Element e) {
    if (e.widget is T && (key == null || e.widget.key == key)) {
      found = e.widget as T;
      return;
    }
    if (found == null) e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

Future<void> main() async {
  if (!const bool.fromEnvironment('ISOLATED_TEST_PACKAGE')) {
    throw StateError('Audio audit requires isolated application ID');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final route = Uri.parse(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  final slug = route.queryParameters['piece'] ?? 'ode-to-joy';
  final tempo = int.tryParse(route.queryParameters['tempo'] ?? '') ?? 80;
  final performing = route.queryParameters['mode'] == 'performance';
  final c = AuditController();
  await c.initialize();
  if (c.error != null) throw StateError(c.error!);
  await c.updateSettings(
    locale: 'zh-Hans',
    onboard: true,
    values: {
      'sound_enabled': true,
      'gain_permille': 850,
      'speech_enabled': false,
    },
  );
  final piece = c.content.pieces.singleWhere((p) => p.id == 'piece-$slug-001');
  runApp(
    MaterialApp(
      initialRoute: '/',
      theme: qinTheme(highContrast: false),
      home: performing
          ? PianoPerformancePage(c: c, piece: piece, tempo: tempo)
          : PianoPiecePage(c: c, piece: piece),
    ),
  );
  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!performing && slug == 'ode-to-joy') {
      await c.preview(0, true, pointer: -20000);
      await Future<void>.delayed(const Duration(seconds: 8));
      final held = await c.platform.call('getAudioState');
      if (held['active_voice_count'] != 1) {
        throw StateError('Sustain did not survive eight seconds');
      }
      await c.preview(0, false, pointer: -20000);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final released = await c.platform.call('getAudioState');
      if (released['active_voice_count'] != 0) {
        throw StateError('Release did not finish');
      }
      debugPrint(
        'AUDIO_SUSTAIN_PROBE ${jsonEncode({'held_after_8s': held, 'released': released})}',
      );
    }
    if (!performing) {
      final slider = findWidget<Slider>(key: const ValueKey('piece-tempo'))!;
      slider.onChanged!(tempo.toDouble());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      findWidget<Slider>(key: const ValueKey('piece-tempo'))!
          .onChangeEnd!(tempo.toDouble());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      debugPrint(
        'AUDIO_AUDIT_BEGIN ${jsonEncode({'piece': slug, 'tempo': tempo, 'clock_us': c.clock.now})}',
      );
      findWidget<OutlinedButton>(key: const ValueKey('piece-audition'))!
          .onPressed!();
    }
    final readyDeadline = c.clock.now + 35000000;
    while ((findWidget<ScrollingScore>() == null ||
            findWidget<ScrollingScore>()!.player.mode !=
                ScrollPieceMode.running) &&
        c.clock.now < readyDeadline) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final player = findWidget<ScrollingScore>()!.player;
    debugPrint(
      'AUDIO_AUDIT_ANCHOR ${jsonEncode({'piece': slug, 'clock_us': c.clock.now, 'elapsed_us': player.elapsedUs, 'tempo': player.tempo})}',
    );
    var backingActive = false;
    final deadline = c.clock.now + player.totalUs + 20000000;
    var lastIndex = -1, paused = false;
    final clockErrors = <int>[];
    final underruns = <int>[];
    while (player.mode == ScrollPieceMode.running && c.clock.now < deadline) {
      final state = await c.platform.call('getAudioState');
      backingActive |= state['piece_backing_playing'] == true;
      if (state['piece_position_us'] is int) {
        clockErrors.add(
          (player.elapsedUs - (state['piece_position_us'] as int)).abs(),
        );
      }
      if (state['underruns'] is int) underruns.add(state['underruns'] as int);
      if (performing) {
        final index = player.currentIndex;
        if (index != null && index != lastIndex && !piece.notes[index].isRest) {
          final keyboard = findWidget<PianoKeyboard>();
          if (keyboard != null) {
            keyboard.onUp(20000, null, false, {});
            keyboard.onDown(20000, piece.notes[index].key, false, {});
          }
          lastIndex = index;
        }
        if (!paused && player.elapsedUs > 2000000) {
          findWidget<IconButton>(key: const ValueKey('performance-pause'))!
              .onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final frozen = player.elapsedUs;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (player.elapsedUs != frozen) {
            throw StateError('Paused score moved');
          }
          findWidget<IconButton>(key: const ValueKey('performance-pause'))!
              .onPressed!();
          while (player.mode == ScrollPieceMode.paused) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          paused = true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final state = await c.platform.call('getAudioState');
    final completedResult = findWidget<PieceResultPage>();
    final saved =
        performing &&
        completedResult != null &&
        c.history.any(
          (r) => r['session_id'] == completedResult.record['session_id'],
        );
    if (performing && !saved) {
      throw StateError('Performance did not save its completion record');
    }
    clockErrors.sort();
    debugPrint(
      'AUDIO_AUDIT_END ${jsonEncode({'piece': slug, 'tempo': player.tempo, 'mode': player.mode.name, 'elapsed_us': player.elapsedUs, 'expected_us': player.totalUs, 'backing_observed_playing': backingActive, 'audio_state': state, 'clock_us': c.clock.now, 'premixed_preview': !performing, 'record_saved': saved, 'pause_resume_checked': paused, 'clock_error_p95_us': clockErrors.isEmpty ? null : clockErrors[(clockErrors.length * .95).floor().clamp(0, clockErrors.length - 1)], 'max_underruns': underruns.isEmpty ? null : underruns.reduce((a, b) => a > b ? a : b)})}',
    );
  }());
}
