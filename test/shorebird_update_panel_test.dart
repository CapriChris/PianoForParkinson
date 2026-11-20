import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/features/shorebird_update_panel.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class FakeUpdater implements ShorebirdUpdater {
  FakeUpdater({
    this.available = true,
    this.status = UpdateStatus.upToDate,
    this.fail = false,
    this.ready = true,
  });
  final bool available;
  final UpdateStatus status;
  final bool fail;
  final bool ready;
  int downloads = 0;
  @override
  bool get isAvailable => available;
  Completer<UpdateStatus>? pending;
  int checks = 0;
  Patch? current;
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checks++;
    if (fail) throw Exception('offline');
    return pending == null ? status : await pending!.future;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    downloads++;
  }

  @override
  Future<Patch?> readCurrentPatch() async => current;
  @override
  Future<Patch?> readNextPatch() async =>
      downloads > 0 && ready ? const Patch(number: 1) : null;
}

void main() {
  testWidgets('ordinary builds explain the required base without download', (
    tester,
  ) async {
    final updater = FakeUpdater(available: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: true, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('检查热更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不支持热更新'), findsOneWidget);
    expect(updater.downloads, 0);
  });
  testWidgets(
    'download prepares next start without restarting or progress percentages',
    (tester) async {
      final updater = FakeUpdater(status: UpdateStatus.outdated);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShorebirdUpdatePanel(chinese: true, updater: updater),
          ),
        ),
      );
      await tester.tap(find.text('检查热更新'));
      await tester.pumpAndSettle();
      expect(updater.downloads, 1);
      expect(find.textContaining('请先完成当前训练'), findsOneWidget);
      expect(find.text('检查热更新'), findsOneWidget);
    },
  );
  testWidgets('offline errors preserve current use and permit retry', (
    tester,
  ) async {
    final updater = FakeUpdater(fail: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: true, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('检查热更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('仍可继续使用当前版本'), findsOneWidget);
    expect(updater.downloads, 0);
  });
  testWidgets(
    'no patch after a download race does not promise a ready update',
    (tester) async {
      final updater = FakeUpdater(status: UpdateStatus.outdated, ready: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShorebirdUpdatePanel(chinese: true, updater: updater),
          ),
        ),
      );
      await tester.tap(find.text('检查热更新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有等待生效的更新'), findsOneWidget);
    },
  );
  testWidgets('latest build remains usable and downloads nothing', (
    tester,
  ) async {
    final updater = FakeUpdater(status: UpdateStatus.upToDate);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: true, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('检查热更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('最新可用版本'), findsOneWidget);
    expect(updater.downloads, 0);
  });
  testWidgets('queued patch reports a cold start in English', (tester) async {
    final updater = FakeUpdater(status: UpdateStatus.restartRequired);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: false, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('Check for patches'));
    await tester.pumpAndSettle();
    expect(find.text('Update ready for the next cold start.'), findsOneWidget);
    expect(updater.downloads, 0);
  });
  testWidgets('the currently running patch is not announced as a new patch', (
    tester,
  ) async {
    final updater = FakeUpdater(status: UpdateStatus.outdated)
      ..current = const Patch(number: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: true, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('检查热更新'));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有等待生效的更新'), findsOneWidget);
  });
  testWidgets('duplicate checks and leaving the page do not interrupt use', (
    tester,
  ) async {
    final updater = FakeUpdater()..pending = Completer<UpdateStatus>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShorebirdUpdatePanel(chinese: true, updater: updater),
        ),
      ),
    );
    await tester.tap(find.text('检查热更新'));
    await tester.tap(find.text('检查热更新'));
    expect(updater.checks, 1);
    await tester.pumpWidget(const SizedBox());
    updater.pending!.complete(UpdateStatus.outdated);
    await tester.pump();
    expect(updater.downloads, 0);
    expect(tester.takeException(), isNull);
  });
}
