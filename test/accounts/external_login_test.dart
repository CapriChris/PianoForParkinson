import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/accounts/account_controller.dart';
import 'package:piano_practice/accounts/account_pages.dart';
import 'package:piano_practice/accounts/external_account_pages.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/platform/wechat_login.dart';

import 'account_api_test.dart';
import 'account_pages_test.dart' show AccountTestApp;

class ExternalTransport extends AuthTransport {
  bool enabled = true, newAccount = false;
  int sends = 0, logins = 0, binds = 0;
  Completer<void>? sending;
  RemoteApiException? sendError;
  Json? lastProof;
  List<Json> identities = [];
  @override
  Future<Json> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    if (path == '/mobile/auth/providers') {
      return {'sms_enabled': enabled, 'wechat_enabled': enabled};
    }
    if (path == '/mobile/auth/identities') return {'items': identities};
    if (path.endsWith('/sms/challenge')) {
      sends++;
      await sending?.future;
      if (sendError != null) throw sendError!;
      return {
        'challenge_id': '44444444-4444-4444-8444-444444444444',
        'expires_in': 300,
        'retry_after': 60,
      };
    }
    if (path.endsWith('/wechat/challenge')) {
      return {
        'challenge_id': '44444444-4444-4444-8444-444444444444',
        'state': 's' * 43,
        'app_id': 'wx0123456789abcdef',
      };
    }
    if (path.endsWith('/sms/login') || path.endsWith('/wechat/login')) {
      logins++;
      lastProof = data as Json;
      return {
        ...response(),
        if (newAccount)
          'recovery_code': 'test-recovery-code-keep-safe-1234567890',
      };
    }
    if (path.endsWith('/sms/bind') || path.endsWith('/wechat/bind')) {
      binds++;
      return {'message': '绑定成功'};
    }
    return super.request(method, path, data: data, query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('piano_training/platform/v1'),
          (call) async => {
            'ok': true,
            'request_id': (call.arguments as Map)['request_id'],
            'data': <String, dynamic>{},
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WechatLogin.channel, null);
  });

  Future<AccountController> phonePage(
    WidgetTester tester,
    ExternalTransport transport, {
    bool available = true,
  }) async {
    final accounts = AccountController(
      vault: MemoryVault(),
      transport: transport,
      appFactory: AccountTestApp.new,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneAccountPage(
          api: accounts.api,
          accounts: accounts,
          available: available,
          now: tester.binding.clock.now,
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      accounts.dispose();
      await tester.pump();
    });
    await tester.pumpAndSettle();
    return accounts;
  }

  Future<void> click(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('unconfigured SMS never sends or admits a user', (tester) async {
    final transport = ExternalTransport()..enabled = false;
    final accounts = await phonePage(tester, transport, available: false);
    expect(find.textContaining('手机号登录暂未开通'), findsOneWidget);
    await click(tester, 'sms-send');
    await click(tester, 'sms-submit');
    expect(transport.sends, 0);
    expect(accounts.app, isNull);
    expect(accounts.api.signedIn, isFalse);
  });

  testWidgets(
    'SMS validates input, prevents duplicate sends and honors cooldown',
    (tester) async {
      final transport = ExternalTransport();
      await phonePage(tester, transport);
      await click(tester, 'sms-send');
      expect(find.text('请输入手机号'), findsOneWidget);
      expect(transport.sends, 0);
      await tester.enterText(
        find.byKey(const ValueKey('sms-phone')),
        '13800138000',
      );
      transport.sending = Completer<void>();
      await click(tester, 'sms-send');
      expect(find.text('发送中…'), findsOneWidget);
      await click(tester, 'sms-send');
      expect(transport.sends, 1);
      transport.sending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('60秒后重发'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.text('获取验证码'), findsOneWidget);
    },
  );

  testWidgets(
    'server Retry-After blocks SMS retry without pretending it was sent',
    (tester) async {
      final transport = ExternalTransport()
        ..sendError = const RemoteApiException(
          429,
          '请稍后重试。',
          retryAfter: Duration(seconds: 120),
        );
      await phonePage(tester, transport);
      await tester.enterText(
        find.byKey(const ValueKey('sms-phone')),
        '13800138000',
      );
      await click(tester, 'sms-send');
      expect(find.text('请稍后重试。'), findsOneWidget);
      expect(find.text('120秒后重发'), findsOneWidget);
      expect(find.text('验证码已发送，请查看短信。'), findsNothing);
      await click(tester, 'sms-send');
      expect(transport.sends, 1);
    },
  );

  testWidgets(
    'changing phone invalidates proof and never logs into another number',
    (tester) async {
      final transport = ExternalTransport();
      final accounts = await phonePage(tester, transport);
      await tester.enterText(
        find.byKey(const ValueKey('sms-phone')),
        '13800138000',
      );
      await click(tester, 'sms-send');
      await tester.enterText(
        find.byKey(const ValueKey('sms-phone')),
        '13900139000',
      );
      await tester.enterText(find.byKey(const ValueKey('sms-code')), '826193');
      await click(tester, 'sms-submit');
      expect(find.text('请先获取当前手机号的有效验证码。'), findsOneWidget);
      expect(transport.logins, 0);
      expect(accounts.app, isNull);
    },
  );

  testWidgets('new SMS user saves recovery code before protected app opens', (
    tester,
  ) async {
    final transport = ExternalTransport()..newAccount = true;
    final accounts = await phonePage(tester, transport);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登录／注册'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('sms-phone')),
      '13800138000',
    );
    await click(tester, 'sms-send');
    await tester.enterText(find.byKey(const ValueKey('sms-code')), '826193');
    await click(tester, 'sms-submit');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('保存账号恢复码'), findsOneWidget);
    expect(accounts.app, isNull);
    expect(transport.lastProof!['sync_consent_version'], 'account-sync-v1');
    await tester.tap(find.text('我已保存'));
    await tester.pumpAndSettle();
    expect(accounts.app, isA<AccountTestApp>());
    expect(transport.logins, 1);
  });

  test('binding reuses the current session and patient identity', () async {
    final transport = ExternalTransport();
    final vault = MemoryVault();
    final api = AccountApi(vault: vault, transport: transport);
    await api.authenticate('patient_one', 'test-pass-123');
    final original = api.session!;
    await api.bindSms('44444444-4444-4444-8444-444444444444', '826193');
    expect(transport.binds, 1);
    expect(identical(api.session, original), isTrue);
    expect(api.session!.directory, original.directory);
    expect(vault.value!.patientId, original.patientId);
  });

  test('native WeChat state mismatch and cancellation fail closed', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      WechatLogin.channel,
      (_) async => {'code': 'code', 'state': 'wrong-state'},
    );
    await expectLater(
      WechatLogin.authorize('wx0123456789abcdef', 's' * 43),
      throwsA(isA<WechatLoginError>()),
    );
    messenger.setMockMethodCallHandler(
      WechatLogin.channel,
      (_) async => throw PlatformException(code: 'WX_CANCELLED'),
    );
    await expectLater(
      WechatLogin.authorize('wx0123456789abcdef', 's' * 43),
      throwsA(
        isA<WechatLoginError>().having((e) => e.message, 'message', '已取消微信授权。'),
      ),
    );
  });

  testWidgets('only phone login is exposed even when server enables WeChat', (
    tester,
  ) async {
    final transport = ExternalTransport();
    final accounts = AccountController(
      vault: MemoryVault(),
      transport: transport,
      appFactory: AccountTestApp.new,
    );
    var nativeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WechatLogin.channel, (_) async {
          nativeCalls++;
          return null;
        });
    await tester.pumpWidget(AccountApplication(accounts: accounts));
    await accounts.restore();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wechat-login')), findsNothing);
    expect(find.textContaining('微信'), findsNothing);
    expect(find.byKey(const ValueKey('phone-login')), findsOneWidget);
    await click(tester, 'phone-login');
    await tester.pumpAndSettle();
    expect(find.byType(PhoneAccountPage), findsOneWidget);
    expect(find.byKey(const ValueKey('sms-send')), findsOneWidget);
    expect(nativeCalls, 0);
    await tester.tap(find.byKey(const ValueKey('phone-back-button')));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneAccountPage), findsNothing);
    expect(find.byKey(const ValueKey('phone-login')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    accounts.dispose();
    await tester.pump();
  });

  testWidgets(
    'account methods hide WeChat binding and status but keep phone binding',
    (tester) async {
      final transport = ExternalTransport()
        ..identities = [
          {'provider': 'wechat', 'label': '已绑定微信'},
        ];
      final api = AccountApi(vault: MemoryVault(), transport: transport);
      await api.authenticate('patient_one', 'test-pass-123');
      final app = AccountTestApp(api, api.session!, () async {}, () {});
      await app.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountLoginMethods(c: app, onBusy: (_) {}, disabled: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('微信'), findsNothing);
      expect(find.text('绑定手机号'), findsOneWidget);
      await tester.tap(find.text('绑定手机号'));
      await tester.pumpAndSettle();
      expect(find.text('确认绑定'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-back-button')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.pump();
    },
  );

  for (final size in [const Size(390, 844), const Size(640, 360)]) {
    testWidgets(
      'phone illustration starts below status bar and back stays above it $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final accounts = AccountController(
          vault: MemoryVault(),
          transport: ExternalTransport(),
          appFactory: AccountTestApp.new,
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                viewPadding: const EdgeInsets.only(top: 24, bottom: 16),
                textScaler: TextScaler.linear(size.width > size.height ? 2 : 1),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PhoneAccountPage(
                        api: accounts.api,
                        accounts: accounts,
                        available: false,
                      ),
                    ),
                  ),
                  child: const Text('open phone'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open phone'));
        await tester.pumpAndSettle();
        final illustration = tester.getRect(
          find.byKey(const ValueKey('account-header-illustration')),
        );
        final back = tester.getRect(
          find.byKey(const ValueKey('phone-back-button')),
        );
        expect(illustration.top, 24);
        expect(illustration.left, 0);
        expect(illustration.width, size.width);
        expect(back.top, 24);
        expect(illustration.contains(back.center), isTrue);
        final codeField = tester.getRect(
          find.byKey(const ValueKey('sms-code')),
        );
        final sendButton = tester.getRect(
          find.byKey(const ValueKey('sms-send')),
        );
        expect(sendButton.left, greaterThan(codeField.right));
        expect(sendButton.center.dy, closeTo(codeField.center.dy, 1));
        await tester.ensureVisible(find.byKey(const ValueKey('sms-submit')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(const ValueKey('phone-back-button'))).top,
          24,
        );
        await tester.tap(find.byKey(const ValueKey('phone-back-button')));
        await tester.pumpAndSettle();
        expect(find.byType(PhoneAccountPage), findsNothing);
        await tester.pumpWidget(const SizedBox());
        accounts.dispose();
        await tester.pump();
      },
    );
  }

  test(
    'retained WeChat API still uses the protected account lifecycle',
    () async {
      final transport = ExternalTransport();
      final accounts = AccountController(
        vault: MemoryVault(),
        transport: transport,
        appFactory: AccountTestApp.new,
      );
      await accounts.authenticateWechat(
        '44444444-4444-4444-8444-444444444444',
        'provider-code',
        's' * 43,
      );
      expect(accounts.app, isNull);
      await accounts.enter();
      expect(accounts.app, isA<AccountTestApp>());
      expect(transport.lastProof!['state'], 's' * 43);
      expect(transport.lastProof!['code'], 'provider-code');
      expect(transport.logins, 1);
      accounts.dispose();
    },
  );
}
