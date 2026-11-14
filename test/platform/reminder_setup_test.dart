import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/platform/reminder_setup.dart';

class FakeReminderSetupGateway implements ReminderSetupGateway {
  bool notifications = false, exact = false, channelEnabled = true;
  bool grantNotifications = true, grantExact = true, unrestricted = false;
  bool startup = false,
      background = false,
      failRead = false,
      failStartup = false;
  String family = 'standard';
  Completer<void>? readGate, startupGate;
  final calls = <String>[];
  @override
  Future<ReminderSetupStatus> read() async {
    await readGate?.future;
    if (failRead) throw StateError('Unavailable');
    return ReminderSetupStatus(
      notificationsAllowed: notifications,
      exactAllowed: exact,
      channelEnabled: channelEnabled,
      family: family,
      batteryUnrestricted: unrestricted,
      startupReviewRecommended: startup,
      backgroundReviewRecommended: background,
    );
  }

  @override
  Future<void> requestNotifications() async {
    calls.add('notifications');
    notifications = grantNotifications;
  }

  @override
  Future<void> requestExact() async {
    calls.add('exact');
    exact = grantExact;
  }

  @override
  Future<void> openNotifications() async {
    calls.add('notificationSettings');
  }

  @override
  Future<void> openStartup() async {
    calls.add('startup');
    if (failStartup) throw StateError('Unavailable');
    await startupGate?.future;
  }

  @override
  Future<void> openBackground() async {
    calls.add('background');
  }
}

void main() {
  test(
    'only standard permissions are automatically requested in order',
    () async {
      final gateway = FakeReminderSetupGateway()
        ..startup = true
        ..background = true;
      final flow = ReminderSetupController(gateway);
      addTearDown(flow.dispose);
      await flow.advance();
      expect(gateway.calls, ['notifications', 'exact']);
      expect(flow.step, ReminderSetupStep.done);
      await flow.resumed();
      expect(gateway.calls, ['notifications', 'exact']);
    },
  );
  test('authorized permissions are skipped', () async {
    final gateway = FakeReminderSetupGateway()
      ..notifications = true
      ..exact = true;
    final flow = ReminderSetupController(gateway);
    addTearDown(flow.dispose);
    await flow.advance();
    expect(gateway.calls, isEmpty);
  });
  test(
    'denial is not retried on resume; settings require explicit retry',
    () async {
      final gateway = FakeReminderSetupGateway()..grantNotifications = false;
      final flow = ReminderSetupController(gateway);
      addTearDown(flow.dispose);
      await flow.advance();
      await flow.resumed();
      expect(gateway.calls, ['notifications']);
      await flow.advance(retry: true);
      expect(gateway.calls, ['notifications', 'notificationSettings']);
      gateway.notifications = true;
      await flow.resumed();
      expect(flow.step, ReminderSetupStep.done);
      expect(gateway.calls.last, 'exact');
    },
  );
  test('blocked channel waits for actual authorization change', () async {
    final gateway = FakeReminderSetupGateway()
      ..notifications = true
      ..exact = true
      ..channelEnabled = false;
    final flow = ReminderSetupController(gateway);
    addTearDown(flow.dispose);
    await flow.advance();
    await flow.resumed();
    expect(gateway.calls, ['notificationSettings']);
    expect(flow.step, ReminderSetupStep.notifications);
    gateway.channelEnabled = true;
    await flow.resumed();
    expect(flow.step, ReminderSetupStep.done);
  });
  test(
    'exact permission is optional without pretending it was granted',
    () async {
      final gateway = FakeReminderSetupGateway()
        ..notifications = true
        ..grantExact = false;
      final flow = ReminderSetupController(gateway);
      addTearDown(flow.dispose);
      await flow.advance();
      await flow.resumed();
      expect(gateway.calls, ['exact']);
      await flow.advance(skipExact: true);
      expect(flow.step, ReminderSetupStep.done);
      expect(flow.status!.exactAllowed, isFalse);
    },
  );
  for (final brand in [
    'vivo',
    'xiaomi',
    'huawei',
    'honor',
    'oppo',
    'meizu',
    'samsung',
    'other',
  ]) {
    test(
      '$brand opens OEM pages only from individual controls and rereads actual status',
      () async {
        final gateway = FakeReminderSetupGateway()
          ..notifications = true
          ..exact = true
          ..startup = true
          ..background = true
          ..family = brand;
        final flow = ReminderSetupController(gateway);
        addTearDown(flow.dispose);
        await flow.advance();
        expect(gateway.calls, isEmpty);
        await flow.openStartupGuide();
        expect(gateway.calls, ['startup']);
        flow.leftApp();
        await flow.resumed();
        expect(gateway.calls, ['startup']);
        expect(flow.startupGuideReturned, isTrue);
        expect(flow.hasUnverifiedSettings, isTrue);
        await flow.openBackgroundGuide();
        expect(gateway.calls, ['startup', 'background']);
        gateway.unrestricted = true;
        flow.leftApp();
        await flow.resumed();
        expect(flow.status!.batteryUnrestricted, isTrue);
      },
    );
  }
  test('OEM launch failure never implies authorization and supports explicit retry', () async {
    final gateway = FakeReminderSetupGateway()
      ..notifications = true
      ..exact = true
      ..failStartup = true;
    final flow = ReminderSetupController(gateway);
    addTearDown(flow.dispose);
    await flow.advance();
    await flow.openStartupGuide();
    expect(flow.failed, isTrue);
    expect(flow.startupOpened, isFalse);
    expect(flow.startupGuideReturned, isFalse);
    gateway.failStartup = false;
    await flow.openStartupGuide();
    expect(flow.failed, isFalse);
    expect(flow.startupOpened, isTrue);
  });
  test(
    'lifecycle return during a manual launch does not open the other OEM page',
    () async {
      final gateway = FakeReminderSetupGateway()
        ..notifications = true
        ..exact = true
        ..startupGate = Completer<void>();
      final flow = ReminderSetupController(gateway);
      addTearDown(flow.dispose);
      await flow.advance();
      final pending = flow.openStartupGuide();
      await Future<void>.delayed(Duration.zero);
      flow.leftApp();
      await flow.resumed();
      gateway.startupGate!.complete();
      await pending;
      expect(gateway.calls, ['startup']);
      expect(flow.startupGuideReturned, isTrue);
      expect(flow.step, ReminderSetupStep.done);
    },
  );
  test('read errors remain retryable without claiming grants', () async {
    final gateway = FakeReminderSetupGateway()..failRead = true;
    final flow = ReminderSetupController(gateway);
    addTearDown(flow.dispose);
    await flow.advance();
    expect(flow.failed, isTrue);
    expect(flow.status, isNull);
    gateway.failRead = false;
    await flow.advance(retry: true);
    expect(flow.failed, isFalse);
  });
  test('disposing a pending read prevents future permission prompts', () async {
    final gateway = FakeReminderSetupGateway()..readGate = Completer<void>();
    final flow = ReminderSetupController(gateway);
    final pending = flow.advance();
    await flow.advance();
    flow.dispose();
    gateway.readGate!.complete();
    await pending;
    expect(gateway.calls, isEmpty);
  });
}
