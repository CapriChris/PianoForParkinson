import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/accounts/account_controller.dart';
import 'package:piano_practice/accounts/account_pages.dart';
import 'package:piano_practice/accounts/account_session.dart';
import 'package:piano_practice/app/app_controller.dart';
import 'package:piano_practice/app/piano_app.dart';

import 'account_api_test.dart';

class AccountTestApp extends AppController {
  AccountTestApp(
    AccountApi api,
    AccountSession session,
    Future<void> Function() logout,
    void Function() invalidated,
  ) : super(
        accountApi: api,
        databaseSubdirectory: session.directory,
        onSignOut: logout,
        onAccountInvalidated: invalidated,
      );
  @override
  Future<void> initialize() async {
    repository.profile = {
      'locale': 'zh-Hans',
      'mode': 'ASSIST',
      'onboarding_completed': 1,
      'settings_json': jsonEncode({
        'sound_enabled': false,
        'gain_permille': 600,
      }),
    };
    initialized = true;
    notifyListeners();
  }

  @override
  Future<void> shutdownAccount() async {
    dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('piano_training/platform/v1'),
      (call) async => {
        'ok': true,
        'request_id': (call.arguments as Map)['request_id'],
        'data': <String, dynamic>{},
      },
    );
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('piano_training/platform/v1'),
      null,
    );
  });

  testWidgets('signed out cannot reach training even on system Back', (
    tester,
  ) async {
    var opened = 0;
    final accounts = AccountController(
      vault: MemoryVault(),
      transport: AuthTransport(),
      appFactory: (api, session, logout, invalid) {
        opened++;
        return AccountTestApp(api, session, logout, invalid);
      },
    );
    await tester.pumpWidget(AccountApplication(accounts: accounts));
    await accounts.restore();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(opened, 0);
    await tester.pumpWidget(const SizedBox());
    accounts.dispose();
    await tester.pump();
  });

  testWidgets('login opens protected app and logout removes all its routes', (
    tester,
  ) async {
    final vault = MemoryVault();
    final accounts = AccountController(
      vault: vault,
      transport: AuthTransport(),
      appFactory: AccountTestApp.new,
    );
    await tester.pumpWidget(AccountApplication(accounts: accounts));
    await accounts.restore();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-username')),
      'patient_one',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'test-password-123',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(vault.value, isNotNull);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('protected route')),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('protected route'), findsOneWidget);
    final logout = accounts.logout();
    await tester.pumpAndSettle();
    await logout;
    await tester.pumpAndSettle();
    expect(find.text('protected route'), findsNothing);
    expect(find.byType(HomePage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(vault.value, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    accounts.dispose();
    await tester.pump();
  });

  testWidgets(
    'valid remembered account opens offline and expired account stays locked',
    (tester) async {
      for (final expired in [false, true]) {
        final saved = savedSession();
        final vault = MemoryVault()
          ..value = AccountSession.parse({
            ...saved.toJson(),
            if (expired)
              'refresh_expires_at': DateTime.now()
                  .subtract(const Duration(days: 1))
                  .toIso8601String(),
          });
        final transport = AuthTransport()..offline = true;
        final accounts = AccountController(
          vault: vault,
          transport: transport,
          appFactory: AccountTestApp.new,
        );
        await tester.pumpWidget(AccountApplication(accounts: accounts));
        await accounts.restore();
        await tester.pumpAndSettle();
        expect(find.byType(HomePage), expired ? findsNothing : findsOneWidget);
        expect(find.byType(LoginPage), expired ? findsOneWidget : findsNothing);
        expect(transport.calls, isEmpty);
        await tester.pumpWidget(const SizedBox());
        accounts.dispose();
        await tester.pump();
      }
    },
  );

  testWidgets('registration has no consent checkbox and validates fields', (
    tester,
  ) async {
    final accounts = AccountController(
      vault: MemoryVault(),
      transport: AuthTransport(),
    );
    await tester.pumpWidget(AccountApplication(accounts: accounts));
    await accounts.restore();
    await tester.pumpAndSettle();
    await tester.tap(find.text('没有账号？注册'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入用户名'), findsOneWidget);
    expect(accounts.app, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    accounts.dispose();
    await tester.pump();
  });

  Future<AccountController> openLogin(WidgetTester tester) async {
    final accounts = AccountController(
      vault: MemoryVault(),
      transport: AuthTransport(),
      appFactory: AccountTestApp.new,
    );
    await tester.pumpWidget(AccountApplication(accounts: accounts));
    await accounts.restore();
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      accounts.dispose();
      await tester.pump();
    });
    return accounts;
  }

  testWidgets(
    'password eye follows field focus and reflects the visible state',
    (tester) async {
      await openLogin(tester);
      final password = find.byKey(const ValueKey('account-password'));
      final eye = find.byKey(const ValueKey('account-password-visibility'));
      final username = find.byKey(const ValueKey('account-username'));
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: username, matching: find.byType(TextField)),
            )
            .decoration!
            .helperText,
        isNull,
      );
      expect(eye, findsNothing);
      expect(find.textContaining('登录后可使用训练'), findsNothing);
      await tester.enterText(password, 'test-password-123');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: eye, matching: find.byIcon(Icons.visibility_off)),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.descendant(of: password, matching: find.byType(TextField)),
      );
      field.controller!.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 5,
      );
      await tester.tap(eye);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: password, matching: find.byType(TextField)),
            )
            .obscureText,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: password, matching: find.byType(TextField)),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 2, extentOffset: 5),
      );
      expect(
        find.descendant(of: eye, matching: find.byIcon(Icons.visibility)),
        findsOneWidget,
      );
      final icon = tester.getRect(
        find.descendant(of: eye, matching: find.byType(Icon)),
      );
      final container = InputDecorator.containerOf(tester.element(eye))!;
      final box = container.localToGlobal(Offset.zero) & container.size;
      expect((icon.center.dy - box.center.dy).abs(), lessThanOrEqualTo(2));
      expect((box.right - icon.right).abs(), lessThanOrEqualTo(12));
      await tester.tap(eye);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: password, matching: find.byType(TextField)),
            )
            .obscureText,
        isTrue,
      );
      await tester.tap(username);
      await tester.pumpAndSettle();
      expect(eye, findsNothing);
    },
  );

  testWidgets(
    'registration counts nickname inside field and confirmation has its own eye',
    (tester) async {
      await openLogin(tester);
      await tester.tap(find.text('没有账号？注册'));
      await tester.pumpAndSettle();
      expect(find.text('3–32 位字母、数字或下划线'), findsOneWidget);
      expect(find.text('姓名或昵称'), findsNothing);
      expect(find.text('昵称'), findsOneWidget);
      expect(find.textContaining('同意将训练记录'), findsNothing);
      final nickname = find.byKey(const ValueKey('account-nickname'));
      await tester.enterText(nickname, '琴🎹');
      await tester.pumpAndSettle();
      final counter = find.byKey(const ValueKey('account-nickname-counter'));
      expect(tester.widget<Text>(counter).data, '2/64');
      final container = InputDecorator.containerOf(tester.element(counter))!;
      final box = container.localToGlobal(Offset.zero) & container.size;
      final counterRect = tester.getRect(counter);
      expect(
        (counterRect.center.dy - box.center.dy).abs(),
        lessThanOrEqualTo(2),
      );
      expect((counterRect.right - box.right).abs(), lessThanOrEqualTo(12));
      final password = find.byKey(const ValueKey('account-password'));
      final confirmation = find.byKey(const ValueKey('account-confirmation'));
      await tester.enterText(password, 'test-password-123');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-password-visibility')),
        findsOneWidget,
      );
      await tester.enterText(confirmation, 'test-password-123');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-password-visibility')),
        findsNothing,
      );
      final eye = find.byKey(const ValueKey('account-confirmation-visibility'));
      expect(
        find.descendant(of: eye, matching: find.byIcon(Icons.visibility_off)),
        findsOneWidget,
      );
      await tester.tap(eye);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: confirmation,
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isFalse,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: password, matching: find.byType(TextField)),
            )
            .obscureText,
        isTrue,
      );
      expect(
        find.descendant(of: eye, matching: find.byIcon(Icons.visibility)),
        findsOneWidget,
      );
    },
  );

  testWidgets('valid registration submits without an extra sync confirmation', (
    tester,
  ) async {
    final accounts = await openLogin(tester);
    await tester.tap(find.text('没有账号？注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-username')),
      'patient_one',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-nickname')),
      '用户',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'test-pass-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-confirmation')),
      'test-pass-123',
    );
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(
      (accounts.api.transport as AuthTransport)
          .registration!['sync_consent_version'],
      'account-sync-v1',
    );
  });

  testWidgets('password recovery has no footer or username helper', (
    tester,
  ) async {
    await openLogin(tester);
    await tester.ensureVisible(find.text('忘记密码'));
    await tester.tap(find.text('忘记密码'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('account-page-title')))
          .data,
      '重置密码',
    );
    expect(find.textContaining('登录后可使用训练'), findsNothing);
    expect(find.text('3–32 位字母、数字或下划线'), findsNothing);
    expect(find.text('账号恢复码'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('account-password-visibility')),
      findsNothing,
    );
  });

  for (final registration in [true, false]) {
    testWidgets(
      'shared illustrated header and contextual password errors ${registration ? 'register' : 'reset'}',
      (tester) async {
        final accounts = await openLogin(tester);
        final link = find.text(registration ? '没有账号？注册' : '忘记密码');
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(
          find.byKey(const ValueKey('account-header-illustration')),
        );
        expect(
          (image.image as AssetImage).assetName,
          'assets/images/42-auth-shared-header.png',
        );
        expect(find.byIcon(Icons.piano_rounded), findsNothing);
        final password = find.byKey(const ValueKey('account-password'));
        final confirmation = find.byKey(const ValueKey('account-confirmation'));
        TextField input(Finder field) => tester.widget<TextField>(
          find.descendant(of: field, matching: find.byType(TextField)),
        );
        expect(input(password).decoration!.helperText, '密码须为8-16位');
        expect(input(confirmation).decoration!.helperText, isNull);
        final submit = find.widgetWithText(
          FilledButton,
          registration ? '注册并登录' : '重置密码',
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          tester.state<FormFieldState<String>>(password).errorText,
          registration ? '请输入密码' : '请输入新密码',
        );
        expect(
          tester.state<FormFieldState<String>>(confirmation).errorText,
          '请再次输入密码',
        );
        await tester.enterText(password, '1234567');
        await tester.enterText(confirmation, '1234567');
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          tester.state<FormFieldState<String>>(password).errorText,
          '密码须为8-16位',
        );
        expect((accounts.api.transport as AuthTransport).registration, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'illustrated account page scrolls on small landscape with large text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openLogin(tester);
      final register = find.text('没有账号？注册');
      await tester.ensureVisible(register);
      await tester.tap(register);
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '注册并登录');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
