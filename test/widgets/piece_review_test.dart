import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/piano_piece.dart';
import 'package:piano_practice/features/piece_review_page.dart';
import 'package:piano_practice/features/piece_review_score.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import '../domain/piece_trace_test.dart' show tracedRecord;
import 'cognitive_pages_test.dart' show mocks;

void main() {
  testWidgets('score card opens from its edge and from its staff', (
    tester,
  ) async {
    final c = AppController();
    mocks(tester, const Size(360, 720), 'zh-Hans', 1, c);
    final record = tracedRecord();
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: Scaffold(
          body: PieceReviewCard(c: c, record: record),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('open-piece-review'));
    await tester.tapAt(tester.getTopLeft(card) + const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(PieceReviewPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('review-staff-0'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PieceReviewPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('note selection seeks immediately without disabling controls', (
    tester,
  ) async {
    final c = AppController(clock: ManualClock());
    mocks(tester, const Size(360, 720), 'zh-Hans', 1, c);
    c.repository.profile['settings_json'] = jsonEncode({
      'high_contrast': false,
      'sound_enabled': true,
      'gain_permille': 600,
      'speech_enabled': false,
    });
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async {
            if (call.method == 'preparePieceBacking') await gate.future;
            return {
              'ok': true,
              'request_id': (call.arguments as Map)['request_id'],
              'data': {
                'accepted': true,
                'prepared': true,
                'running': true,
                'position_us': 0,
              },
            };
          },
        );
    final record = tracedRecord();
    final piece = PianoPiece.fromJson(record['score_snapshot'] as Json);
    await tester.pumpWidget(
      MaterialApp(
        theme: qinTheme(highContrast: false),
        home: PieceReviewPage(c: c, record: record, piece: piece),
      ),
    );
    await tester.pumpAndSettle();
    final staff = find.byKey(const ValueKey('review-staff-0'));
    await Scrollable.ensureVisible(tester.element(staff), alignment: .05);
    await tester.pumpAndSettle();
    final painter =
        tester.widget<CustomPaint>(staff).painter! as ReviewStaffPainter;
    await tester.tapAt(
      tester.getTopLeft(staff) + painter.g.rect(piece.notes[1]).center,
    );
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('review-seek'))).value,
      painter.data.tickUs(piece.notes[1].startTick),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('review-play')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('review-demo-mode')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('准备中…'), findsNothing);
    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    c.previewInterruptions.value++;
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  for (final size in [const Size(360, 720), const Size(800, 360)]) {
    for (final locale in ['zh-Hans', 'en']) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'whole interactive score, taps and real-track replay $size $locale $scale',
          (tester) async {
            final clock = ManualClock(),
                c = AppController(clock: ManualClock());
            mocks(tester, size, locale, scale, c);
            c.repository.profile['settings_json'] = jsonEncode({
              'high_contrast': false,
              'sound_enabled': true,
              'gain_permille': 600,
              'speech_enabled': false,
            });
            final calls = <MethodCall>[];
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('piano_training/platform/v1'),
                  (call) async {
                    calls.add(call);
                    return {
                      'ok': true,
                      'request_id': (call.arguments as Map)['request_id'],
                      'data': {
                        'accepted': true,
                        'prepared': true,
                        'running': true,
                        'position_us': 0,
                      },
                    };
                  },
                );
            final record = tracedRecord(),
                piece = PianoPiece.fromJson(record['score_snapshot'] as Json);
            await tester.pumpWidget(
              MaterialApp(
                theme: qinTheme(highContrast: false),
                home: PieceReviewPage(c: c, record: record, piece: piece),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(ReviewStaff), findsNWidgets(piece.bars));
            await tester.tap(find.byKey(const ValueKey('review-options')));
            await tester.pumpAndSettle();
            for (final id in ['pauses', 'follow']) {
              final toggle = find.byKey(ValueKey('review-$id-switch'));
              final help = find.byKey(ValueKey('review-$id-help'));
              final before = tester.widget<Switch>(toggle).value;
              await tester.ensureVisible(help);
              await tester.pumpAndSettle();
              await tester.tap(help);
              await tester.pumpAndSettle();
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.tap(find.text(locale == 'en' ? 'Got it' : '知道了'));
              await tester.pumpAndSettle();
              // Reading help must not change the associated replay setting.
              expect(tester.widget<Switch>(toggle).value, before);
              await tester.ensureVisible(toggle);
              await tester.pumpAndSettle();
              await tester.tap(toggle);
              await tester.pumpAndSettle();
              expect(tester.widget<Switch>(toggle).value, !before);
              await tester.tap(toggle);
              await tester.pumpAndSettle();
            }
            final done = find.text(locale == 'en' ? 'Done' : '完成');
            await tester.ensureVisible(done);
            await tester.pumpAndSettle();
            await tester.tap(done);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final staff = find.byKey(const ValueKey('review-staff-0'));
            final firstNote = piece.notes[0];
            final label = locale == 'en'
                ? '${piece.keyLabel(firstNote.key)}, ${firstNote.beats} beats'
                : '${piece.keyLabel(firstNote.key)}，${firstNote.beats} 拍';
            final noteSemantics = find
                .byWidgetPredicate(
                  (w) =>
                      w is Semantics &&
                      w.properties.label == label &&
                      w.properties.onTap != null,
                )
                .first;
            await Scrollable.ensureVisible(
              tester.element(noteSemantics),
              alignment: .3,
            );
            await tester.pumpAndSettle();
            final painter =
                tester.widget<CustomPaint>(staff).painter!
                    as ReviewStaffPainter;
            final offset =
                tester.getTopLeft(staff) +
                painter.g.rect(piece.notes[0]).center;
            await tester.tapAt(offset);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 20));
            final tapped =
                calls
                        .lastWhere((c) => c.method == 'preparePieceBacking')
                        .arguments
                    as Map;
            expect(tapped['solo'], true);
            expect(tapped['melody'], hasLength(1));
            expect(
              tapped['melody'][0]['note_id'],
              piece.playback(piece.notes[0].key).sample,
            );
            final touch = find.byKey(const ValueKey('recorded-touch-1'));
            await Scrollable.ensureVisible(
              tester.element(touch),
              alignment: .3,
            );
            await tester.pump();
            await tester.tapAt(tester.getCenter(touch));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            final wrongTone =
                calls
                        .lastWhere((c) => c.method == 'preparePieceBacking')
                        .arguments
                    as Map;
            expect(wrongTone['melody'][0]['note_id'], piece.playback(0).sample);
            final play = find.byKey(const ValueKey('review-play'));
            await tester.tap(play);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 16));
            final replay =
                calls
                        .lastWhere((c) => c.method == 'preparePieceBacking')
                        .arguments
                    as Map;
            expect(replay['melody'], hasLength(4));
            expect(replay['melody'][1]['note_id'], piece.playback(0).sample);
            expect(replay['melody'][3]['start_us'], 3700000);
            expect(replay['replay_duration_us'], 34000000);
            expect(replay['release_cuts'], [1500000]);
            c.previewInterruptions.value++;
            await tester.pumpAndSettle();
            expect(
              calls.where((c) => c.method == 'stopPieceBacking'),
              isNotEmpty,
            );
            expect(tester.takeException(), isNull);
            expect(clock.now, 0);
            await tester.pumpWidget(const SizedBox());
            c.dispose();
            await tester.pump();
          },
        );
      }
    }
  }
  testWidgets(
    'legacy score gets reference only, never a fabricated user replay',
    (tester) async {
      final c = AppController();
      mocks(tester, const Size(360, 720), 'zh-Hans', 1, c);
      final r = tracedRecord()..remove('performance_trace');
      final p = PianoPiece.fromJson(r['score_snapshot'] as Json);
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: PieceReviewPage(c: c, record: r, piece: p),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('review-user-mode')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('旧记录未保存按键过程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
