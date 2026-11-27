import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/waterfall_score.dart';
import 'package:piano_practice/ui/qin_components.dart';
import 'package:piano_practice/ui/qin_theme.dart';
import 'package:piano_practice/ui/spotlight_tour.dart';

Future<void> advance(WidgetTester tester, [int ms = 800]) async {
  for (var i = 0; i < ms; i += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> next(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('spotlight-next')));
  await tester.tap(find.byKey(const ValueKey('spotlight-next')));
  await advance(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'first-use spotlight guides home, piano setup and training without starting music',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'spotlight-${uuid()}');
      await c.initialize();
      await c.updateSettings(
        locale: 'zh-Hans',
        onboard: true,
        values: {...c.settings, 'spotlight_guides_enabled': true},
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: qinTheme(highContrast: false),
          home: HomePage(c: c),
        ),
      );
      await advance(tester, 1600);
      expect(find.byKey(const ValueKey('spotlight-next')), findsOneWidget);
      debugPrint('SPOTLIGHT_HOME_READY');
      await advance(tester, 3000);
      for (var i = 0; i < 5; i++) {
        await next(tester);
      }
      expect(c.settings['spotlight_home_v1'], true);
      expect(find.byKey(const ValueKey('spotlight-next')), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(QinNavigationBar),
          matching: find.text('练习'),
        ),
      );
      await advance(tester);
      final piece = find.text('弹奏训练');
      await tester.scrollUntilVisible(
        piece,
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(piece);
      await tester.tap(piece);
      await advance(tester, 1600);
      expect(find.byKey(const ValueKey('spotlight-next')), findsOneWidget);
      debugPrint('SPOTLIGHT_PIANO_READY');
      await advance(tester, 3000);
      for (var i = 0; i < 6; i++) {
        await next(tester);
        if (i < 5) {
          debugPrint(
            [
              'SPOTLIGHT_MODE_RECT',
              'SPOTLIGHT_SPEED_RECT',
              'SPOTLIGHT_PREVIEW_RECT',
              'SPOTLIGHT_CAPTURE_RECT',
              'SPOTLIGHT_START_RECT',
            ][i],
          );
          await advance(tester, 2500);
        }
      }
      expect(c.settings['spotlight_piano_v1'], true);
      await tester.tap(find.byKey(const ValueKey('enter-performance')));
      await advance(tester, 1800);
      expect(find.byType(PianoPerformancePage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('confirm-performance-start')),
        findsNothing,
      );
      final player = tester
          .widget<WaterfallScore>(find.byType(WaterfallScore))
          .player;
      expect(player.mode, ScrollPieceMode.ready);
      expect(
        tester
            .widget<SpotlightTour>(find.byType(SpotlightTour))
            .steps
            .first
            .shape,
        SpotlightShape.none,
      );
      expect(find.textContaining('现在先认识界面'), findsNothing);
      debugPrint('SPOTLIGHT_PLAY_READY');
      await advance(tester, 3000);
      for (var i = 0; i < 3; i++) {
        await next(tester);
      }
      expect(c.settings['spotlight_play_v1'], true);
      expect(
        find.byKey(const ValueKey('confirm-performance-start')),
        findsOneWidget,
      );
      expect(player.mode, ScrollPieceMode.ready);
      expect(c.history, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await advance(tester);
      c.dispose();
    },
    skip: !const bool.fromEnvironment('SPOTLIGHT_TEST'),
  );
}
