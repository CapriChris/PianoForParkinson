import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/domain/task_engine.dart';
import 'package:piano_practice/features/training_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';
import 'package:piano_practice/ui/qin_components.dart';

import '../domain/responsive_controls_test.dart' show advanceTo;
import '../domain/task_engine_test.dart' show ready;
import 'phrase_finish_test.dart' show CounterController;
import 'cognitive_pages_test.dart' show mocks;

Future<void> open(
  WidgetTester tester,
  CounterController c,
  String task,
  String locale,
) async {
  mocks(tester, const Size(800, 400), locale, 1, c);
  // Exercise the real training page without unrelated directory/navigation UI.
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale == 'en' ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: qinTheme(highContrast: false),
      home: TrainingPage(c: c, taskId: task),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder item(int number, int planned) => find.textContaining(
  RegExp(
    r'· '
    '$number'
    r'\s*/\s*'
    '$planned',
  ),
);

Future<void> refresh(WidgetTester tester, CounterController c) async {
  c.trainingUpdates.value++;
  await tester.pump();
}

Future<void> close(WidgetTester tester, CounterController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void finishMemoryNotes(TaskEngine e) {
  final clock = e.clock as ManualClock;
  for (final key in List<int>.from(e.expected)) {
    e.down(1, key);
    clock.now += e.noteDurationUs;
    e.up(1);
  }
}

void main() {
  for (final locale in ['zh-Hans', 'en']) {
    final recorded = locale == 'en' ? 'Recorded' : '已记录';
    testWidgets(
      'G1 $locale immediately acknowledges input with continuous feedback',
      (tester) async {
        final c = CounterController();
        await open(tester, c, 'G1_MEMORY', locale);
        final e = c.engine!, clock = e.clock as ManualClock;
        expect(item(1, e.planned), findsOneWidget);
        final keys = List<int>.from(e.expected);
        for (final key in keys.take(keys.length - 1)) {
          e.down(1, key);
          clock.now += e.noteDurationUs;
          e.up(1);
        }
        e.down(1, keys.last);
        clock.now += e.noteDurationUs;
        await refresh(tester, c);
        expect(e.phase, 'response');
        expect(find.text(recorded), findsNothing);
        e.up(1);
        expect(e.phase, 'tail');
        expect(e.completed, 0);
        await refresh(tester, c);
        expect(find.text(recorded), findsOneWidget);
        expect(find.textContaining('正在收尾'), findsNothing);
        expect(find.textContaining('Finishing this item'), findsNothing);
        expect(item(1, e.planned), findsOneWidget);
        expect(find.byType(QinPanel), findsOneWidget);
        final feedback = find.byKey(const ValueKey('recorded-item-feedback'));
        final receiptElement = tester.element(feedback);
        final receiptPosition = tester.getTopLeft(find.text(recorded));
        clock.now += 299999;
        e.tick();
        await refresh(tester, c);
        expect(e.phase, 'tail');
        expect(tester.element(feedback), same(receiptElement));
        expect(item(1, e.planned), findsOneWidget);
        clock.now++;

        e.tick();
        expect(e.phase, 'trialFeedback');
        await refresh(tester, c);
        expect(find.text(recorded), findsOneWidget);
        expect(item(1, e.planned), findsOneWidget);
        expect(tester.element(feedback), same(receiptElement));
        expect(tester.getTopLeft(find.text(recorded)), receiptPosition);
        ready(e, clock);
        await refresh(tester, c);
        expect(find.text(recorded), findsNothing);
        expect(item(2, e.planned), findsOneWidget);
        await close(tester, c);
      },
    );

    testWidgets(
      'G1 $locale receipt persists while tail extra input is scored',
      (tester) async {
        final c = CounterController();
        await open(tester, c, 'G1_MEMORY', locale);
        final e = c.engine!, clock = e.clock as ManualClock;
        finishMemoryNotes(e);
        await refresh(tester, c);
        final feedback = find.byKey(const ValueKey('recorded-item-feedback'));
        final receiptElement = tester.element(feedback);
        expect(find.text(recorded), findsOneWidget);
        e.down(2, e.expected.first);
        clock.now += 300000;
        e.tick();
        expect(e.phase, 'release');
        expect(e.completed, 0);
        await refresh(tester, c);
        expect(find.text(recorded), findsOneWidget);
        expect(item(1, e.planned), findsOneWidget);
        expect(tester.element(feedback), same(receiptElement));
        e.up(2);
        expect(e.phase, 'trialFeedback');
        expect(e.completed, 1);
        expect(e.attempts.last['result']['extra_count'], 1);
        expect(e.attempts.last['result']['full_correct'], false);
        await refresh(tester, c);
        expect(find.text(recorded), findsOneWidget);
        expect(item(1, e.planned), findsOneWidget);
        expect(tester.element(feedback), same(receiptElement));
        await close(tester, c);
      },
    );

    testWidgets(
      'G1 $locale block boundary has one recorded message and counter',
      (tester) async {
        final c = CounterController();
        await open(tester, c, 'G1_MEMORY', locale);
        final e = c.engine!, clock = e.clock as ManualClock;
        for (var i = 0; i < e.trialCount; i++) {
          if (i > 0) ready(e, clock);
          finishMemoryNotes(e);
          await refresh(tester, c);
          expect(find.text(recorded), findsOneWidget);
          expect(item(i + 1, e.planned), findsOneWidget);
          clock.now += 300000;
          e.tick();
        }
        expect(e.phase, 'feedback');
        await refresh(tester, c);
        expect(find.text(recorded), findsOneWidget);
        expect(find.textContaining('这一组已完成'), findsNothing);
        expect(find.textContaining('This block is complete'), findsNothing);
        expect(item(e.completed, e.planned), findsOneWidget);
        expect(
          find.text(locale == 'en' ? 'Next block' : '开始下一组'),
          findsOneWidget,
        );
        e.nextBlock();
        ready(e, clock);
        await refresh(tester, c);
        expect(item(e.completed + 1, e.planned), findsOneWidget);
        await close(tester, c);
      },
    );

    for (final task in ['G2_INHIBITION', 'G3_SWITCH', 'M2_DUAL_ZONE']) {
      testWidgets(
        '$task $locale recorded gap retains completed item on pause',
        (tester) async {
          final c = CounterController();
          await open(tester, c, task, locale);
          final e = c.engine!, clock = e.clock as ManualClock;
          clock.now += e.responseRemainingUs!;
          e.tick();
          expect(e.phase, 'intertrial');
          expect(e.trialIndex, 1);
          expect(e.completed, 1);
          await refresh(tester, c);
          expect(find.text(recorded), findsOneWidget);
          expect(item(1, e.planned), findsOneWidget);
          expect(item(2, e.planned), findsNothing);
          if (task == 'G3_SWITCH') {
            final rule = e.displayedRule == 'POSITION'
                ? (locale == 'en' ? 'Rule A · Match position' : '规则 A · 按位置')
                : (locale == 'en' ? 'Rule B · Match shape' : '规则 B · 按图形');
            expect(find.text(rule), findsOneWidget);
          }
          e.pause('USER');
          clock.now += 5000000;
          expect(e.currentItemNumber, 1);
          e.resume();
          await refresh(tester, c);
          expect(find.text(recorded), findsOneWidget);
          expect(item(1, e.planned), findsOneWidget);
          ready(e, clock);
          await refresh(tester, c);
          expect(find.text(recorded), findsNothing);
          expect(item(2, e.planned), findsOneWidget);
          expect(tester.takeException(), isNull);
          await close(tester, c);
        },
      );
    }

    for (final task in ['S2_RHYTHM', 'M1_ALTERNATE']) {
      testWidgets(
        '$task $locale counter waits for visible beat, not next window',
        (tester) async {
          final c = CounterController();
          await open(tester, c, task, locale);
          final e = c.engine!, clock = e.clock as ManualClock;
          final firstBeat = e.base + e.scheduledBeatUs;
          final nextBeat = firstBeat + 60000000 ~/ e.bpm;
          advanceTo(e, clock, firstBeat + e.beatAfterUs);
          expect(e.completed, 1);
          expect(e.trialIndex, 1);
          await refresh(tester, c);
          expect(item(1, e.planned), findsOneWidget);
          advanceTo(e, clock, nextBeat - 1);
          await refresh(tester, c);
          expect(item(1, e.planned), findsOneWidget);
          advanceTo(e, clock, nextBeat);
          await refresh(tester, c);
          expect(item(2, e.planned), findsOneWidget);
          expect(tester.takeException(), isNull);
          await close(tester, c);
        },
      );
    }

    testWidgets('S1 $locale holding a note is not labeled recorded', (
      tester,
    ) async {
      final c = CounterController();
      await open(tester, c, 'S1_GUIDED', locale);
      final e = c.engine!, clock = e.clock as ManualClock;
      e.down(1, e.expected.single);
      expect(e.phase, 'release');
      expect(e.completed, 0);
      await refresh(tester, c);
      expect(find.text(recorded), findsNothing);
      expect(item(1, e.planned), findsOneWidget);
      clock.now += e.noteDurationUs;
      e.up(1);
      expect(e.completed, 1);
      ready(e, clock);
      await refresh(tester, c);
      expect(item(2, e.planned), findsOneWidget);
      await close(tester, c);
    });
  }
}
