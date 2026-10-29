import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/piano_pieces_page.dart';
import 'package:piano_practice/features/piece_sheet_preview.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

class _FailingPreferences extends MemoryPreferences {
  @override
  Future<void> settingsUpdate({
    String? locale,
    String? mode,
    Json? settings,
    bool onboard = false,
  }) async {
    throw StateError('write failed');
  }
}

void main() {
  testWidgets('each piano piece remembers its selected tempo after reopening', (
    tester,
  ) async {
    final repository = MemoryPreferences();
    final c = AppController(repository: repository);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    await tester.runAsync(c.content.load);
    final first = c.content.pieces[0], second = c.content.pieces[1];
    Future<void> showPiece(int index) async {
      final piece = c.content.pieces[index];
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PianoPiecePage(key: ValueKey(piece.id), c: c, piece: piece),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(int value) async {
      final finder = find.byKey(const ValueKey('piece-tempo'));
      final slider = tester.widget<Slider>(finder);
      slider.onChanged!(value.toDouble());
      await tester.pump();
      tester.widget<Slider>(finder).onChangeEnd!(value.toDouble());
      await tester.pumpAndSettle();
      expect(
        tester.widget<PieceSheetPreview>(find.byType(PieceSheetPreview)).tempo,
        value,
      );
    }

    await showPiece(0);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('piece-tempo'))).value,
      first.tempo,
    );
    await choose(80);
    await showPiece(1);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('piece-tempo'))).value,
      second.tempo,
    );
    await choose(40);
    await showPiece(0);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('piece-tempo'))).value,
      80,
    );
    expect((c.settings['piece_tempos'] as Map)[first.id], 80);
    expect((c.settings['piece_tempos'] as Map)[second.id], 40);
    final reopened = AppController(repository: repository)..initialized = true;
    expect(reopened.pieceTempo(first.id, first.tempo), 80);
    expect(reopened.pieceTempo(second.id, second.tempo), 40);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    reopened.dispose();
    await tester.pump();
  });

  testWidgets('concurrent tempo changes keep each piece and other settings', (
    tester,
  ) async {
    final repository = MemoryPreferences();
    final c = AppController(repository: repository);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    final originalSound = c.settings['sound_enabled'];
    await Future.wait([
      c.savePieceTempo('piece-a', 50),
      c.savePieceTempo('piece-b', 70),
      c.saveTextScale(110),
    ]);
    expect(c.pieceTempo('piece-a', 60), 50);
    expect(c.pieceTempo('piece-b', 60), 70);
    expect(c.settings['text_size_percent_v3'], 110);
    expect(c.settings['sound_enabled'], originalSound);
    c.dispose();
    await tester.pump();
  });

  testWidgets('invalid saved tempo falls back to score default', (
    tester,
  ) async {
    final repository = MemoryPreferences();
    final c = AppController(repository: repository);
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    repository.profile['settings_json'] = canonical({
      ...c.settings,
      'piece_tempos': {'piece-a': 999},
    });
    expect(c.pieceTempo('piece-a', 60), 60);
    c.dispose();
    await tester.pump();
  });
  testWidgets('failed tempo save drops the pending value', (tester) async {
    final c = AppController(repository: _FailingPreferences());
    mocks(tester, const Size(360, 800), 'zh-Hans', 1, c);
    final save = c.savePieceTempo('piece-a', 80);
    expect(c.pieceTempo('piece-a', 60), 80);
    await expectLater(save, throwsStateError);
    expect(c.pieceTempo('piece-a', 60), 60);
    c.dispose();
    await tester.pump();
  });
}
