import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/features/reminder_setup_page.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import '../platform/reminder_setup_test.dart' show FakeReminderSetupGateway;

void main() {
  testWidgets(
    'display settings remain available without requesting more permissions',
    (tester) async {
      final gateway = FakeReminderSetupGateway()
        ..notifications = true
        ..exact = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: ReminderSetupPage(chinese: true, gateway: gateway),
        ),
      );
      await tester.pumpAndSettle();
      final display = find.byKey(const ValueKey('reminder-display-settings'));
      await tester.ensureVisible(display);
      await tester.tap(display);
      await tester.pumpAndSettle();
      expect(gateway.calls, ['notificationSettings']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'each OEM control opens only its own settings and keeps unknown state honest',
    (tester) async {
      final gateway = FakeReminderSetupGateway()
        ..notifications = true
        ..exact = true
        ..startup = true
        ..background = true
        ..family = 'xiaomi';
      await tester.pumpWidget(
        MaterialApp(
          theme: qinTheme(highContrast: false),
          home: ReminderSetupPage(chinese: true, gateway: gateway),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
      final startup = find.byKey(const ValueKey('reminder-startup-open'));
      await tester.ensureVisible(startup);
      await tester.pumpAndSettle();
      await tester.tap(startup);
      await tester.pumpAndSettle();
      expect(gateway.calls, ['startup']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.calls, ['startup']);
      final background = find.byKey(const ValueKey('reminder-background-open'));
      await tester.ensureVisible(background);
      await tester.pumpAndSettle();
      await tester.tap(background);
      await tester.pumpAndSettle();
      expect(gateway.calls, ['startup', 'background']);
      gateway.unrestricted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('需核实：请以系统设置为准'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final chinese in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'permission denial remains usable at 320dp, zh=$chinese scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final gateway = FakeReminderSetupGateway()
            ..notifications = true
            ..grantExact = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: qinTheme(highContrast: false),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ReminderSetupPage(chinese: chinese, gateway: gateway),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final skip = find.byKey(const ValueKey('reminder-setup-skip-exact'));
          expect(skip.hitTestable(), findsOneWidget);
          await tester.tap(skip);
          await tester.pumpAndSettle();
          expect(find.text(chinese ? '完成' : 'Done'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
