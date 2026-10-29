import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/features/touch_check_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'portrait M2 entry opens landscape check; native proof required and back restores portrait',
    (tester) async {
      final c = AppController(databaseSubdirectory: 'dual-entry-${uuid()}');
      await c.initialize();
      expect(c.error, isNull);
      final root = c.capabilities['storage_path'] as String;
      final path = '$root/${c.databaseSubdirectory}';
      addTearDown(() async {
        c.dispose();
        if (c.repository.db.isOpen) await c.repository.db.close();
        final dir = Directory(path).absolute;
        if (!dir.path.startsWith(
              '${Directory(root).absolute.path}${Platform.pathSeparator}',
            ) ||
            !dir.path.endsWith(c.databaseSubdirectory!)) {
          throw StateError('Unsafe cleanup');
        }
        if (await dir.exists()) await dir.delete(recursive: true);
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      });
      await c.updateSettings(locale: 'zh-Hans', onboard: true);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await tester.pumpWidget(PianoApp(controller: c));
      await tester.pumpAndSettle();
      Future<void> waitOrientation(Type page, bool landscape) async {
        for (var i = 0; i < 100; i++) {
          final size = MediaQuery.sizeOf(tester.element(find.byType(page)));
          if ((size.width > size.height) == landscape) return;
          await tester.pump(const Duration(milliseconds: 20));
        }
        fail('Orientation did not become landscape=$landscape');
      }

      await waitOrientation(HomePage, false);
      await tester.scrollUntilVisible(
        find.text('练习双区').hitTestable(),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('双区配合'), findsOneWidget);
      expect(find.byType(TouchCheckPage), findsNothing);
      const capture = bool.fromEnvironment('CAPTURE_ENTRY');
      if (capture) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await binding.takeScreenshot('qinban-0.1.14-portrait-entry');
      }
      await tester.tap(find.text('练习双区'));
      await tester.pumpAndSettle();
      await waitOrientation(TouchCheckPage, true);
      await tester.pumpAndSettle();
      expect(
        MediaQuery.sizeOf(tester.element(find.byType(TouchCheckPage))).width,
        greaterThanOrEqualTo(600),
      );
      expect(find.text('检查双触点支持'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '完成检查，继续'))
            .onPressed,
        isNull,
      );
      expect(c.engine, isNull);
      expect((await c.repository.historyPage()).records, isEmpty);
      if (capture) await binding.takeScreenshot('qinban-0.1.14-touch-check');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await waitOrientation(HomePage, false);
      expect(find.text('练习双区'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
