// Run with --dart-define=ISOLATED_TEST_PACKAGE=true and MP3_IMPORT_TEST=true.
// Put the generated C4/E4/G4 fixture in Download/qinban-import-check.mp3.
// Select that file when the Android document picker opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piece_timing.dart';
import 'package:piano_practice/domain/scrolling_piece.dart';
import 'package:piano_practice/features/keyboard.dart';
import 'package:piano_practice/features/music_import_page.dart';
import 'package:piano_practice/features/piano_performance_page.dart';
import 'package:piano_practice/features/piece_sheet_preview.dart';
import 'package:piano_practice/features/waterfall_score.dart';
import 'package:piano_practice/ui/qin_theme.dart';

Future<void> advance(WidgetTester tester, int milliseconds) async {
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'waterfall wait, successful hold, native MP3 import and original-audio playback',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'waterfall-flow-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      expect(c.audioReady, isTrue);
      await c.updateSettings(
        locale: 'zh-Hans',
        onboard: true,
        values: {...c.settings, 'sound_enabled': true},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPerformancePage(
            c: c,
            piece: c.content.pieces.first,
            tempo: 30,
            practiceMode: PiecePracticeMode.beginner,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-performance-start')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-performance-start')));
      await advance(tester, 12500);
      final player = tester
          .widget<WaterfallScore>(find.byType(WaterfallScore))
          .player;
      expect(player.waitingForKey, isTrue);
      expect(player.elapsedUs, 0);
      debugPrint('SNAPSHOT_WATERFALL_READY');
      await advance(tester, 30000);
      expect(player.elapsedUs, 0);
      final rect = tester.getRect(find.byType(PianoKeyboard));
      final width =
          (rect.width - (player.piece.keyCount - 1) * 8) /
          player.piece.keyCount;
      final key = player.piece.notes.first.key;
      final gesture = await tester.startGesture(
        Offset(rect.left + key * (width + 8) + width / 2, rect.center.dy),
      );
      while (player.elapsedUs < player.noteEndUs(0) - 40000) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await gesture.up();
      await advance(tester, 500);
      debugPrint('FIRST_HOLD ${player.trace.notes.first}');
      expect(player.trace.notes.first['success'], isTrue);
      expect(player.trace.notes.first['waiting_us'], greaterThan(9000000));
      expect(player.waitingForKey, isTrue);
      await tester.tap(find.byKey(const ValueKey('performance-pause')));
      await tester.pumpAndSettle();
      expect(player.mode, ScrollPieceMode.paused);
      final frozen = player.elapsedUs;
      await tester.tap(find.byKey(const ValueKey('performance-pause')));
      await advance(tester, 1000);
      expect(player.mode, ScrollPieceMode.paused);
      await advance(tester, 2500);
      expect(player.mode, ScrollPieceMode.running);
      expect(player.elapsedUs, frozen);

      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => MusicImportPage(c: c),
                    ),
                  ),
                  child: const Text('Open import'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 MP3'));
      debugPrint('WAITING_FOR_MP3_PICKER');
      for (
        var i = 0;
        i < 240 && find.byType(PieceSheetPreview).evaluate().isEmpty;
        i++
      ) {
        await advance(tester, 500);
      }
      expect(find.byType(PieceSheetPreview), findsOneWidget);
      final preview = tester.widget<PieceSheetPreview>(
        find.byType(PieceSheetPreview),
      );
      expect(
        preview.piece.notes
            .where((note) => !note.isRest)
            .map((note) => preview.piece.keyMidi(note.key)),
        [60, 64, 67],
      );
      debugPrint('SNAPSHOT_MP3_PREVIEW_READY');
      await advance(tester, 6000);
      await tester.tap(find.text('确认并保存曲目'));
      await tester.pumpAndSettle();
      expect(c.settings['imported_pieces'], hasLength(1));
      final imported = c.content.pieces.last;
      expect(imported.accompaniment?['kind'], 'local_mp3');
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPerformancePage(c: c, piece: imported, tempo: 30),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('confirm-performance-start')),
      );
      await tester.tap(find.byKey(const ValueKey('confirm-performance-start')));
      await advance(tester, 12500);
      final importedPlayer = tester
          .widget<WaterfallScore>(find.byType(WaterfallScore))
          .player;
      expect(importedPlayer.mode, ScrollPieceMode.running);
      expect(importedPlayer.elapsedUs, greaterThan(0));
      expect(
        (await c.platform.call('getAudioState'))['piece_backing_playing'],
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('performance-pause')));
      await tester.pumpAndSettle();
      expect(importedPlayer.mode, ScrollPieceMode.paused);
      final importedFrozen = importedPlayer.elapsedUs;
      await tester.tap(find.byKey(const ValueKey('performance-pause')));
      await advance(tester, 1000);
      expect(importedPlayer.mode, ScrollPieceMode.paused);
      await advance(tester, 2500);
      expect(importedPlayer.mode, ScrollPieceMode.running);
      expect(importedPlayer.elapsedUs, greaterThan(importedFrozen));
      expect(
        (await c.platform.call('getAudioState'))['piece_backing_playing'],
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await c.repository.clear();
      c.dispose();
    },
    skip: !const bool.fromEnvironment('MP3_IMPORT_TEST'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
