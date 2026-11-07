import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/scrolling_score.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import '../domain/scrolling_piece_test.dart' show score;
import 'cognitive_pages_test.dart' show mocks;

void main() {
  testWidgets(
    'piece notifications keep time; takeover needs manual preparation and cannot restart a cancelled resume',
    (tester) async {
      final clock = ManualClock();
      final c = AppController(clock: clock);
      mocks(tester, const Size(800, 400), 'zh-Hans', 1, c);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPerformancePage(c: c, piece: score(), tempo: 60),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final player = tester
          .widget<ScrollingScore>(find.byType(ScrollingScore))
          .player;
      expect(player.mode, ScrollPieceMode.running);
      clock.now = 5000000;
      await tester.pump(const Duration(milliseconds: 16));
      c.didChangeAppLifecycleState(AppLifecycleState.inactive);
      c.handlePlaybackEvent('AUDIO_FOCUS_DUCK');
      await tester.pump();
      expect(player.mode, ScrollPieceMode.running);
      c.handlePlaybackEvent('WINDOW_FOCUS_LOST');
      await tester.pump();
      final position = player.elapsedUs;
      expect(player.mode, ScrollPieceMode.paused);
      c.handlePlaybackEvent('WINDOW_FOCUS_GAIN');
      c.handlePlaybackEvent('AUDIO_FOCUS_GAIN');
      c.didChangeAppLifecycleState(AppLifecycleState.resumed);
      clock.now += 10000000;
      await tester.pump(const Duration(seconds: 1));
      expect(player.mode, ScrollPieceMode.paused);
      expect(player.elapsedUs, position);

      final resume = find.byKey(const ValueKey('performance-pause'));
      await tester.tap(resume);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('准备继续 · 3'), findsOneWidget);
      expect(player.mode, ScrollPieceMode.paused);
      c.handlePlaybackEvent('AUDIO_FOCUS_LOST');
      await tester.pump(const Duration(seconds: 2));
      expect(player.mode, ScrollPieceMode.paused);
      expect(find.textContaining('准备继续'), findsNothing);

      await tester.tap(resume);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(player.mode, ScrollPieceMode.running);
      expect(player.elapsedUs, position);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      c.dispose();
    },
  );
}
