import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/features/plans_page.dart';
import 'package:piano_practice/platform/plan_reminders.dart';
import 'package:piano_practice/ui/qin_press.dart';
import 'package:piano_practice/ui/qin_theme.dart';

import 'cognitive_pages_test.dart' show mocks;
import 'rhythm_pages_test.dart' show MemoryPreferences;

class ReadyReminders extends PlanReminders {
  @override
  Future<PlanReminderAccess> access() async => PlanReminderAccess.ready;
}

void main() {
  AppController controller(
    WidgetTester tester, {
    String locale = 'zh-Hans',
    double scale = 1,
  }) {
    final c = AppController(repository: MemoryPreferences());
    mocks(tester, const Size(320, 640), locale, scale, c);
    addTearDown(c.dispose);
    return c;
  }

  Widget app(AppController c, {Key? instanceKey, int cards = 1}) => MaterialApp(
    theme: qinTheme(highContrast: false),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            for (var i = 0; i < cards; i++)
              PlanReminderSetupHint(
                key: instanceKey ?? ValueKey(i),
                c: c,
                reminders: ReadyReminders(),
              ),
          ],
        ),
      ),
    ),
  );

  testWidgets(
    'temporary dismissal hides only this instance; recreating the page restores it',
    (tester) async {
      final c = controller(tester);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      expect(find.text('提醒设置'), findsOneWidget);
      expect(find.text('一键设置提醒'), findsNothing);
      expect(find.text('通知与准时提醒已开启。请进入提醒设置，检查自启动和后台活动。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-hint-close')));
      await tester.pumpAndSettle();
      expect(find.text('请确保已开启所需权限后再选择“不再提醒”'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reminder-hint-once')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-hint-close')), findsNothing);
      expect(
        c.settings[PlanReminderSetupHint.hiddenPreferenceKey],
        isNot(true),
      );
      await tester.pumpWidget(app(c, instanceKey: const ValueKey('new-page')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-hint-close')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'permanent dismissal hides both plan and editor hints and survives recreation',
    (tester) async {
      final c = controller(tester);
      await tester.pumpWidget(app(c, cards: 2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-hint-close')).first);
      await tester.pumpAndSettle();
      final button = tester.widget<QinOutlinedButton>(
        find.byKey(const ValueKey('reminder-hint-never')),
      );
      expect(
        button.style!.foregroundColor!.resolve({}),
        const Color(0xffb3261e),
      );
      await tester.tap(find.byKey(const ValueKey('reminder-hint-never')));
      await tester.pumpAndSettle();
      expect(c.settings[PlanReminderSetupHint.hiddenPreferenceKey], isTrue);
      expect(find.byKey(const ValueKey('reminder-hint-close')), findsNothing);
      await tester.pumpWidget(app(c, instanceKey: const ValueKey('new-page')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-hint-close')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final locale in ['zh-Hans', 'en']) {
    testWidgets(
      'closing dialog without a choice retains the hint at large text $locale',
      (tester) async {
        final c = controller(tester, locale: locale, scale: 2);
        await tester.pumpWidget(app(c));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-hint-close')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('reminder-hint-once')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reminder-hint-once')).hitTestable(),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reminder-hint-close')),
          findsOneWidget,
        );
        expect(
          c.settings[PlanReminderSetupHint.hiddenPreferenceKey],
          isNot(true),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
