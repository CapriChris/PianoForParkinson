import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/accounts/account_pages.dart';
import 'package:piano_practice/app/app_controller.dart';

import 'account_api_test.dart';
import 'patient_name_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
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
  for (final english in [false, true]) {
    testWidgets('name editor at 2x text ${english ? 'English' : 'Chinese'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final transport = ProfileTransport();
      final api = AccountApi(vault: MemoryVault(), transport: transport);
      await api.authenticate('patient_one', 'password');
      final c = AppController(accountApi: api);
      c.repository.profile = {'locale': english ? 'en' : 'zh-Hans'};
      c.initialized = true;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: AccountPage(c: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('patient_one'), findsNothing);
      final edit = find.byKey(const ValueKey('edit-patient-name'));
      expect(edit, findsOneWidget);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('patient-name-input')),
        '李小明',
      );
      await tester.tap(find.byKey(const ValueKey('save-patient-name')));
      await tester.pumpAndSettle();
      expect(api.session!.name, '李小明');
      expect(transport.submitted!['expected_name'], '医护新姓名');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pumpAndSettle();
    });
  }
  testWidgets(
    '409 refreshes canonical name and requires a second confirmation',
    (tester) async {
      final transport = ProfileTransport();
      final api = AccountApi(vault: MemoryVault(), transport: transport);
      await api.authenticate('patient_one', 'password');
      final c = AppController(accountApi: api);
      c.repository.profile = {'locale': 'zh-Hans'};
      c.initialized = true;
      await tester.pumpWidget(MaterialApp(home: AccountPage(c: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-patient-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('patient-name-input')),
        '我的姓名',
      );
      transport.conflict = true;
      transport.name = '医生刚修改';
      await tester.tap(find.byKey(const ValueKey('save-patient-name')));
      await tester.pumpAndSettle();
      expect(transport.submitted!['expected_name'], '医护新姓名');
    expect(api.session!.name, '医生刚修改');
      expect(find.text('确认保存姓名'), findsOneWidget);
      expect(find.textContaining('医生刚修改'), findsWidgets);
      transport.conflict = false;
      await tester.tap(find.byKey(const ValueKey('save-patient-name')));
      await tester.pumpAndSettle();
      expect(transport.submitted!['expected_name'], '医生刚修改');
      expect(api.session!.name, '我的姓名');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'failed secure persistence keeps editor open without saved notice',
    (tester) async {
      final transport = ProfileTransport();
      final vault = MemoryVault();
      final api = AccountApi(vault: vault, transport: transport);
      await api.authenticate('patient_one', 'password');
      final c = AppController(accountApi: api);
      c.repository.profile = {'locale': 'en'};
      c.initialized = true;
      await tester.pumpWidget(MaterialApp(home: AccountPage(c: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-patient-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('patient-name-input')),
        'Changed',
      );
      vault.failWrite = true;
      await tester.tap(find.byKey(const ValueKey('save-patient-name')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('patient-name-error')), findsOneWidget);
      expect(find.text('Name saved'), findsNothing);
      expect(api.session!.name, '医护新姓名');
      expect(api.signedIn, isTrue);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets('old dialog cannot rename a switched account', (tester) async {
    final transport = ProfileTransport();
    final api = AccountApi(vault: MemoryVault(), transport: transport);
    await api.authenticate('patient_one', 'password');
    final c = AppController(accountApi: api);
    c.repository.profile = {'locale': 'en'};
    c.initialized = true;
    await tester.pumpWidget(MaterialApp(home: AccountPage(c: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-patient-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('patient-name-input')),
      'Old account edit',
    );
    api.signOut();
    transport.userId = '33333333-3333-4333-8333-333333333333';
    await api.authenticate('patient_two', 'password');
    await tester.tap(find.byKey(const ValueKey('save-patient-name')));
    await tester.pumpAndSettle();
    expect(transport.submitted, isNull);
    expect(api.session!.name, '测试用户');
    expect(find.text('Name saved'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pumpAndSettle();
  });
}
