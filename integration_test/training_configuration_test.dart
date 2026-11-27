import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/piece_sheet_preview.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/waterfall_score.dart';
import 'package:piano_practice/ui/qin_theme.dart';

Future<void> advance(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms; i += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('configuration, drawer, waterfall preview and frozen count-in', (
    tester,
  ) async {
    final c = AppController(databaseSubdirectory: 'configuration-${uuid()}');
    await c.initialize();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    expect(c.audioReady, isTrue);
    await c.updateSettings(
      locale: 'zh-Hans',
      onboard: true,
      values: {...c.settings, 'sound_enabled': true},
    );
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('home-host'),
        debugShowCheckedModeBanner: false,
        theme: qinTheme(highContrast: false),
        home: HomePage(c: c),
      ),
    );
    await tester.pumpAndSettle();
    final assistant = tester.getRect(
      find.byKey(const ValueKey('home-assistant')),
    );
    final recommendation = tester.getRect(
      find.byKey(const ValueKey('home-recommendation')),
    );
    final more = tester.getRect(
      find.byKey(const ValueKey('home-other-practices')),
    );
    expect(assistant.bottom, lessThan(recommendation.top));
    expect(recommendation.bottom, lessThan(more.top));
    debugPrint('HOME_ORDER_READY');
    await tester.tap(find.text('练习').last);
    await tester.pumpAndSettle();
    final special = find.byKey(const ValueKey('special-practices'));
    await tester.scrollUntilVisible(
      special,
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('特色练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('特色练习'));
    await tester.pumpAndSettle();
    expect(find.byType(PracticeCard), findsNWidgets(7));
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('configuration-host'),
        debugShowCheckedModeBanner: false,
        theme: qinTheme(highContrast: false),
        home: PianoPiecePage(
          c: c,
          piece: c.content.pieces.firstWhere((piece) => piece.keyCount == 6),
        ),
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('CONFIGURATION_SCREEN_READY');
    await advance(tester, 4000);
    await tester.tap(
      find.text(
        c.content.pieces
            .firstWhere((piece) => piece.keyCount == 6)
            .title(c.locale),
      ),
    );
    await tester.pumpAndSettle();
    debugPrint('SONG_DRAWER_SCREEN_READY');
    await advance(tester, 4000);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('piece-audition')),
      180,
    );
    await tester.pumpAndSettle();
    expect(find.byType(WaterfallScore), findsOneWidget);
    await tester.ensureVisible(find.byType(PieceSheetPreview));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('piece-audition')));
    await advance(tester, 4600);
    final keys = tester.widget<PianoKeyboard>(find.byType(PianoKeyboard));
    expect(keys.locked, isTrue);
    expect(keys.demonstratingKeys, isNotEmpty);
    expect(
      tester
          .widget<WaterfallScore>(find.byType(WaterfallScore))
          .demonstratingNotes,
      isNotEmpty,
    );
    debugPrint('PREVIEW_SCREEN_READY');
    await advance(tester, 4000);
    await tester.tap(find.byKey(const ValueKey('enter-performance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-performance-start')));
    await advance(tester, 1000);
    final player = tester
        .widget<WaterfallScore>(find.byType(WaterfallScore))
        .player;
    expect(player.mode, ScrollPieceMode.ready);
    final frozen = player.elapsedUs;
    await advance(tester, 1000);
    expect(player.elapsedUs, frozen);
    await advance(tester, 2000);
    expect(player.mode, ScrollPieceMode.running);
    expect(player.elapsedUs, lessThan(0));
    debugPrint('PERFORMANCE_SCREEN_READY');
    await advance(tester, 4000);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    c.dispose();
  }, skip: !const bool.fromEnvironment('TRAINING_UI_TEST'));
}
