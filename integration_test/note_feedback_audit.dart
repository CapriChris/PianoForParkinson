// Visual validation only. Never launch this entry point under the main app ID.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/features/key_mark.dart';
import 'package:piano_practice/features/key_press_feedback.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/features/switch_tutorial_page.dart';
import 'package:piano_practice/features/cognitive_cue.dart';
import 'package:piano_practice/ui/qin_theme.dart';

List<Element> elements(bool Function(Widget) matches) {
  final result = <Element>[];
  void visit(Element e) {
    if (matches(e.widget)) result.add(e);
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return result;
}

T one<T extends Widget>({Key? key}) =>
    elements((w) => w is T && (key == null || w.key == key)).single.widget as T;

void pointer(int key, int id, bool down) {
  final e = elements(
    (w) => w is KeyPressFeedback && w.key == ValueKey('key-feedback-$key'),
  ).single;
  final box = e.findRenderObject()! as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
    down
        ? PointerDownEvent(pointer: id, position: point)
        : PointerUpEvent(pointer: id, position: point),
  );
}

Future<void> main() async {
  if (!const bool.fromEnvironment('ISOLATED_TEST_PACKAGE')) {
    throw StateError('Isolated package required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final uri = Uri.parse(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
  final mode = uri.queryParameters['mode'] ?? 'preview';
  final c = AppController(databaseSubdirectory: 'note-feedback-0140');
  await c.initialize();
  if (c.error != null) throw StateError(c.error!);
  await c.updateSettings(
    locale: 'zh-Hans',
    onboard: true,
    values: {'sound_enabled': false, 'speech_enabled': false},
  );
  if (mode != 'performance') {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  final piece = c.content.pieces.singleWhere(
    (p) =>
        p.id ==
        'piece-${mode == 'performance' ? 'happy-birthday' : 'ode-to-joy'}-001',
  );
  runApp(
    MaterialApp(
      initialRoute: '/',
      theme: qinTheme(highContrast: false),
      home: mode == 'performance'
          ? PianoPerformancePage(c: c, piece: piece, tempo: 80)
          : mode == 'other'
          ? SwitchTutorialPage(c: c)
          : PianoPiecePage(c: c, piece: piece),
    ),
  );
  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mode == 'preview') {
      one<OutlinedButton>(key: const ValueKey('piece-audition')).onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 4300));
      if (elements((w) => w is KeyMark).isNotEmpty ||
          elements((w) => w is ShapeMark).isNotEmpty) {
        throw StateError('Piece preview still shows shape marks');
      }
      final frames = elements(
        (w) => w is CustomPaint && w.painter is KeyParticlesPainter,
      );
      if (!frames.any(
        (e) => (e.widget as CustomPaint).painter is KeyParticlesPainter,
      )) {
        throw StateError('No preview feedback');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1700));
    } else {
      if (mode == 'performance') {
        final deadline = c.clock.now + 12000000;
        while ((elements((w) => w is ScrollingScore).isEmpty ||
                one<ScrollingScore>().player.targetKey == null) &&
            c.clock.now < deadline) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (one<PianoKeyboard>().showKeyMarks) {
          throw StateError('Piece keyboard still shows shapes');
        }
      }
      final count = mode == 'performance' ? one<PianoKeyboard>().count : 1;
      final colors = <int>[];
      for (var i = 0; i < count; i++) {
        pointer(i, 900 + i, true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      var animated = 0;
      for (final e in elements(
        (w) => w is CustomPaint && w.painter is KeyParticlesPainter,
      )) {
        final painter =
            (e.widget as CustomPaint).painter! as KeyParticlesPainter;
        if (painter.animation.value > 0 && painter.animation.value < 1) {
          animated++;
        }
      }
      for (var i = 0; i < count; i++) {
        final feedback = one<KeyPressFeedback>(
          key: ValueKey('key-feedback-$i'),
        );
        colors.add(
          ((feedback.child as Container).decoration! as BoxDecoration).color!
              .toARGB32(),
        );
      }
      if (animated < count) {
        throw StateError('Not all presses animated: $animated/$count');
      }
      if (mode == 'performance' && colors.first != colors.last) {
        throw StateError('Octave colors differ');
      }
      if (mode == 'other' && elements((w) => w is ShapeMark).length < 3) {
        throw StateError('Rule shapes were removed');
      }
      debugPrint(
        'FEEDBACK_AUDIT_PRESS ${jsonEncode({'mode': mode, 'animated': animated, 'colors': colors, 'clock_us': c.clock.now})}',
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      for (var i = 0; i < count; i++) {
        pointer(i, 900 + i, false);
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (elements((w) => w is CustomPaint && w.painter is KeyParticlesPainter)
          .any(
            (e) =>
                ((e.widget as CustomPaint).painter! as KeyParticlesPainter)
                    .animation
                    .status ==
                AnimationStatus.forward,
          )) {
        throw StateError('Feedback did not settle');
      }
    }
    debugPrint(
      'FEEDBACK_AUDIT_END ${jsonEncode({'mode': mode, 'visual_only': true, 'clock_us': c.clock.now})}',
    );
  }());
}
