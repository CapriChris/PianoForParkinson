// Synthetic performances generated through the production recorder, isolated DB only.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piece_performance.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piece_result_page.dart';
import 'package:piano_practice/features/piece_review_score.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';

List<Element> elements(bool Function(Widget) test) {
  final result = <Element>[];
  void visit(Element e) {
    if (test(e.widget)) result.add(e);
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return result;
}

Future<void> tap(Key key) async {
  final e = elements((w) => w.key == key).single;
  await Scrollable.ensureVisible(
    e,
    alignment: .25,
    duration: const Duration(milliseconds: 100),
  );
  await Future<void>.delayed(const Duration(milliseconds: 180));
  final b = e.findRenderObject()! as RenderBox,
      p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: 222, position: p),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: 222, position: p),
  );
}

Future<void> ready() async {
  await Future<void>.delayed(const Duration(milliseconds: 70));
  for (var i = 0; i < 200; i++) {
    final button = elements((w) => w.key == const ValueKey('review-play'))
        .first
        .widget;
    if (button is FilledButton && button.onPressed != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('Review preparation timeout');
}

Future<void> main() async {
  if (!const bool.fromEnvironment('ISOLATED_TEST_PACKAGE')) {
    throw StateError('Isolated package required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final mode =
      Uri.parse(WidgetsBinding.instance.platformDispatcher.defaultRouteName)
          .queryParameters['mode'] ??
      'score';
  final c = AppController(databaseSubdirectory: 'piece-review-0144');
  await c.initialize();
  if (c.error != null) throw StateError(c.error!);
  await c.updateSettings(
    locale: 'zh-Hans',
    onboard: true,
    values: {
      'sound_enabled': true,
      'gain_permille': 800,
      'speech_enabled': false,
    },
  );
  final piece = c.content.pieces.first, clock = ManualClock();
  final player = ScrollingPiecePlayer(piece, clock, tempo: 60)
    ..start(leadBeats: 0);
  player.down(1, 2);
  clock.now = 600000;
  player.up(1);
  clock.now = 900000;
  player.down(2, 0);
  clock.now = 1100000;
  player.up(2);
  clock.now = 1200000;
  player.down(3, 2);
  clock.now = 1800000;
  player.up(3);
  clock.now = 2000000;
  player.pause();
  clock.now = 3000000;
  player.resume();
  clock.now = 3200000;
  player.down(4, 3);
  clock.now = 3900000;
  player.up(4);
  clock.now = 4400000;
  player.down(5, 1);
  clock.now = 4800000;
  player.up(5);
  clock.now = player.totalUs + 1000000;
  player.tick();
  var record = PiecePerformance.completed(
    player,
    DateTime.now().subtract(const Duration(minutes: 2)),
  );
  PiecePerformance.validate(record);
  await c.repository.savePiecePerformance(record);
  await c.repository.savePiecePerformance(record);
  final rows = await c.repository.db.query(
    'piece_performances',
    where: 'session_id=?',
    whereArgs: [record['session_id']],
  );
  if (rows.length != 1) throw StateError('Record retry was not idempotent');
  final restored = PiecePerformance.fromRow(
    Map<String, dynamic>.from(rows.single),
  );
  if (canonical(restored) != canonical(record)) {
    throw StateError('Record round trip changed');
  }
  record = restored;
  if (mode == 'legacy') {
    record = {...record}
      ..remove('score_snapshot')
      ..remove('performance_trace');
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: qinTheme(highContrast: false),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      home: mode == 'audition'
          ? PianoPiecePage(c: c, piece: piece)
          : PieceResultPage(c: c, record: record, alreadySaved: true),
    ),
  );
  unawaited(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mode == 'audition') {
      await tap(const ValueKey('piece-audition'));
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      var state = await c.platform.call('getAudioState');
      if (state['piece_backing_playing'] != true) {
        throw StateError('Original audition regressed');
      }
      debugPrint(
        'REVIEW_AUDIT_READY ${jsonEncode({'mode': mode, 'synthetic': true, 'state': state})}',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      c.interruptPlayback('AUDIT_END');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      state = await c.platform.call('getAudioState');
      if (state['piece_backing_playing'] == true) {
        throw StateError('Audition did not stop');
      }
      debugPrint(
        'REVIEW_AUDIT_END ${jsonEncode({'mode': mode, 'synthetic': true, 'state': state})}',
      );
      return;
    }
    await tap(const ValueKey('open-piece-review'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final staffs = elements((w) => w is ReviewStaff);
    if (staffs.where((e) => (e.widget as ReviewStaff).measure == 15).isEmpty) {
      throw StateError('Incomplete score');
    }
    if (mode == 'score') {
      final staff = elements((w) => w.key == const ValueKey('review-staff-0'))
          .last;
      await Scrollable.ensureVisible(
        staff,
        alignment: .1,
        duration: const Duration(milliseconds: 120),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final painter =
          (staff.widget as CustomPaint).painter! as ReviewStaffPainter;
      final box = staff.findRenderObject()! as RenderBox;
      final point = box.localToGlobal(painter.g.rect(piece.notes[0]).center);
      GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 224, position: point),
      );
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: 224, position: point),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ready();
      final state = await c.platform.call('getAudioState');
      if (state['piece_backing_playing'] != true) {
        throw StateError('Note preview did not play');
      }
      debugPrint(
        'REVIEW_AUDIT_READY ${jsonEncode({'mode': mode, 'synthetic': true, 'round_trip': true, 'state': state})}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final ended = await c.platform.call('getAudioState');
      if (ended['piece_backing_playing'] == true) {
        throw StateError('Note preview did not settle');
      }
      debugPrint(
        'REVIEW_AUDIT_END ${jsonEncode({'mode': mode, 'synthetic': true, 'state': ended})}',
      );
    } else {
      if (mode == 'legacy') {
        final user =
            elements((w) => w.key == const ValueKey('review-user-mode'))
                    .single
                    .widget
                as OutlinedButton;
        if (user.onPressed != null) {
          throw StateError('Fabricated legacy replay');
        }
      }
      if (mode == 'replay') {
        await tap(const ValueKey('review-options'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final toggle =
            elements(
                  (w) =>
                      w is SwitchListTile &&
                      w.title is Text &&
                      (w.title as Text).data == '同步伴奏',
                ).single.widget
                as SwitchListTile;
        toggle.onChanged!(false);
        final done =
            elements(
                  (w) =>
                      w is FilledButton &&
                      w.child is Text &&
                      (w.child as Text).data == '完成',
                ).single.widget
                as FilledButton;
        done.onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await tap(const ValueKey('review-play'));
      await ready();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      var state = await c.platform.call('getAudioState');
      if (state['piece_backing_playing'] != true) {
        throw StateError('Replay did not start');
      }
      debugPrint(
        'REVIEW_AUDIT_READY ${jsonEncode({'mode': mode, 'synthetic': true, 'round_trip': true, 'trace_notes': 5, 'state': state})}',
      );
      if (mode == 'transport') {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await tap(const ValueKey('review-play'));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        state = await c.platform.call('getAudioState');
        if (state['piece_backing_playing'] == true) {
          throw StateError('Pause failed');
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tap(const ValueKey('review-play'));
        await ready();
        final slider =
            elements((w) => w.key == const ValueKey('review-seek'))
                    .single
                    .widget
                as Slider;
        slider.onChangeStart!(10000000);
        slider.onChanged!(10000000);
        slider.onChangeEnd!(10000000);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        state = await c.platform.call('getAudioState');
        if (state['piece_position_us'] < 9800000 ||
            state['piece_position_us'] > 11000000) {
          throw StateError('Seek failed: $state');
        }
        c.interruptPlayback('AUDIT');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        state = await c.platform.call('getAudioState');
        if (state['piece_backing_playing'] == true ||
            state['active_voice_count'] != 0) {
          throw StateError('Interruption leaked audio');
        }
        await tap(const ValueKey('review-play'));
        await ready();
      }
      if (mode == 'transport') {
        final slider =
            elements((w) => w.key == const ValueKey('review-seek'))
                    .single
                    .widget
                as Slider;
        slider.onChangeStart!(64000000);
        slider.onChanged!(64400000);
        slider.onChangeEnd!(64400000);
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        final completed = await c.platform.call('getAudioState');
        if (completed['piece_backing_playing'] == true) {
          throw StateError('Replay did not complete from its tail');
        }
      }
      await Future<void>.delayed(Duration(seconds: mode == 'replay' ? 8 : 1));
      c.interruptPlayback('AUDIT_END');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      state = await c.platform.call('getAudioState');
      if (state['piece_backing_playing'] == true ||
          state['active_voice_count'] != 0) {
        throw StateError('Audio did not stop');
      }
      debugPrint(
        'REVIEW_AUDIT_END ${jsonEncode({'mode': mode, 'synthetic': true, 'state': state})}',
      );
    }
  }());
}
