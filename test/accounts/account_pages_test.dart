import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_app.dart';
import 'package:piano_practice/accounts/account_pages.dart';
import 'package:piano_practice/accounts/account_session.dart';

import 'account_session_test.dart' show AccountApi, MemorySecureStore;

void main() {
  testWidgets(
    'production gate exposes login only and system back cannot expose training',
    (tester) async {
      final session = AccountSession(
        store: MemorySecureStore(),
        api: AccountApi(DateTime.now()),
      );
      await tester.pumpWidget(
        AccountApplication(session: session, usePlatform: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录'), findsWidgets);
      expect(find.text('注册账号'), findsOneWidget);
      expect(find.text('开始训练'), findsNothing);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      expect(await nav.maybePop(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('注册账号'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets(
    'registration requires explicit consent and hands recovery code to user',
    (tester) async {
      final api = AccountApi(DateTime.now());
      final session = AccountSession(store: MemorySecureStore(), api: api);
      bool hold = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountAuthPage(
            session: session,
            holdRecovery: (v) => hold = v,
          ),
        ),
      );
      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(0), 'account_qa');
      await tester.enterText(inputs.at(1), 'QA');
      await tester.enterText(inputs.at(2), 'correct-password');
      await tester.enterText(inputs.at(3), 'correct-password');
      final submit = find.text('注册并登录');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(session.signedIn, isFalse);
      expect(find.text('请确认训练记录与计划的自动同步说明。'), findsOneWidget);
      final check = find.byType(CheckboxListTile);
      expect(tester.widget<CheckboxListTile>(check).value, isFalse);
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(session.signedIn, isTrue);
      expect(hold, isTrue);
      expect(find.text('保存一次性恢复码'), findsOneWidget);
      await tester.tap(find.text('我已保存'));
      await tester.pumpAndSettle();
      expect(hold, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
