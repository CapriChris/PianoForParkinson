import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/platform/plan_reminders.dart';

void main() {
  test('fixed GMT offsets preserve hours and minutes', () {
    expect(
      notificationLocation('GMT+05:30').currentTimeZone.offset,
      const Duration(hours: 5, minutes: 30),
    );
    expect(
      notificationLocation('GMT-03:30').currentTimeZone.offset,
      const Duration(hours: -3, minutes: -30),
    );
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'accurate reminder setup is explicit and rechecks existing access',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      var allowed = true, exact = false, quiet = false;
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('dexterous.com/flutter/local_notifications'),
        (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'areNotificationsEnabled':
            case 'requestNotificationsPermission':
              return allowed;
            case 'getNotificationChannels':
              return [
                {
                  'id': PlanReminders.channelId,
                  'name': '训练计划提醒',
                  'importance': quiet ? 0 : 4,
                  'showBadge': true,
                  'bypassDnd': false,
                  'playSound': true,
                  'enableLights': false,
                  'enableVibration': true,
                  'ledColor': 0,
                },
              ];
            case 'canScheduleExactNotifications':
              return exact;
            case 'requestExactAlarmsPermission':
              exact = true;
              return true;
            default:
              return true;
          }
        },
      );
      final service = PlanReminders();
      expect(await service.request(), isTrue);
      expect(await service.access(), PlanReminderAccess.inexact);
      expect(calls, isNot(contains('requestExactAlarmsPermission')));
      await service.configure();
      expect(await service.access(), PlanReminderAccess.ready);
      await service.configure();
      expect(calls.where((c) => c == 'requestExactAlarmsPermission').length, 1);
      quiet = true;
      expect(await service.access(), PlanReminderAccess.channelQuiet);
      await service.configure();
      expect(calls.where((c) => c == 'openAppNotificationSettings').length, 1);
      allowed = false;
      expect(await service.access(), PlanReminderAccess.notificationsOff);
      await service.configure();
      expect(calls.where((c) => c == 'openAppNotificationSettings').length, 2);
    },
  );

  test('resuming preserves overdue pending alarms but cancels edited or disabled ones', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    for (final sql in DatabaseSafety.migration4.split(';')) {
      if (sql.trim().isNotEmpty) await db.execute(sql);
    }
    final calls = <MethodCall>[];
    var pending = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => 'Asia/Shanghai',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          'pendingNotificationRequests' => pending,
          'canScheduleExactNotifications' => false,
          _ => true,
        };
      },
    );
    // Also exercise the date boundary: yesterday's alarm can still be pending.
    // The plugin also checks the real system clock. Keep this midnight fixture
    // in the future instead of letting a fixed calendar date expire.
    final future = DateTime.now().toUtc().add(const Duration(days: 2));
    final date = DateTime.utc(future.year, future.month, future.day);
    var now = date.add(const Duration(hours: 15, minutes: 59, seconds: 30));
    final service = PlanReminders(clock: () => now);
    final store = TrainingScheduleRepository(db, 'p');
    final plan = <String, dynamic>{
      'id': 'overdue',
      'title': 'Pending reminder',
      'kind': 'dance',
      'start': date.toIso8601String().substring(0, 10),
      'end': null,
      'days': <int>[],
      'target_type': 'count',
      'target': 1,
      'reminder': true,
      'paused': false,
      'hour': 23,
      'minute': 59,
    };
    // Schedule before 23:59, then resume just after midnight in Shanghai.
    now = now.subtract(const Duration(minutes: 1));
    await store.savePlan(plan);
    await service.sync(store);
    final scheduled =
        calls.singleWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    pending = [
      {'id': scheduled['id'], 'payload': scheduled['payload']},
    ];
    now = date.add(const Duration(hours: 16, seconds: 15));
    calls.clear();
    await service.sync(store);
    expect(calls.where((c) => c.method == 'cancel'), isEmpty);
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    await store.savePlan({...plan, 'minute': 58});
    calls.clear();
    await service.sync(store);
    expect(calls.where((c) => c.method == 'cancel').length, 1);
    await store.savePlan({...plan, 'paused': true});
    calls.clear();
    await service.sync(store);
    expect(calls.where((c) => c.method == 'cancel').length, 1);
  });

  test('saving checks notification permission and never opens exact-alarm settings', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    var allowed = true, grant = false;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'getNotificationAppLaunchDetails' => {
                'notificationLaunchedApp': false,
              },
              'areNotificationsEnabled' => allowed,
              'requestNotificationsPermission' => grant,
              'canScheduleExactNotifications' => false,
              _ => true,
            };
          },
        );
    final reminders = PlanReminders();
    expect(await reminders.request(), isTrue);
    expect(calls, isNot(contains('requestNotificationsPermission')));
    expect(calls, isNot(contains('requestExactAlarmsPermission')));
    allowed = false;
    expect(await reminders.request(), isFalse);
    grant = true;
    expect(await reminders.request(), isTrue);
    expect(calls.where((c) => c == 'requestNotificationsPermission').length, 2);
    expect(calls, isNot(contains('requestExactAlarmsPermission')));
  });
  test('reminders use high importance, local time, stable IDs and cancel disabled plans', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    for (final sql in DatabaseSafety.migration4.split(';')) {
      if (sql.trim().isNotEmpty) await db.execute(sql);
    }
    final calls = <MethodCall>[];
    var exact = true, permission = true;
    var timeZone = 'Asia/Shanghai';
    var pending = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (_) async => timeZone,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'pendingNotificationRequests' => pending,
          'getNotificationAppLaunchDetails' => {
            'notificationLaunchedApp': false,
          },
          'areNotificationsEnabled' ||
          'requestNotificationsPermission' => permission,
          'canScheduleExactNotifications' ||
          'requestExactAlarmsPermission' => exact,
          _ => true,
        };
      },
    );
    final reminders = PlanReminders();
    expect(await reminders.request(), isTrue);
    final now = tz.TZDateTime.now(tz.getLocation('Asia/Shanghai'));
    final day = DateTime(now.year, now.month, now.day + 1);
    final store = TrainingScheduleRepository(db, 'p');
    final plan = <String, dynamic>{
      'id': 'one',
      'title': '测试提醒',
      'kind': 'dance',
      'start': localDay(day),
      'end': null,
      'days': <int>[],
      'target_type': 'count',
      'target': 1,
      'reminder': true,
      'paused': false,
      'hour': 10,
      'minute': 20,
    };
    await store.savePlan(plan);
    await reminders.sync(store);
    Map args() =>
        calls.lastWhere((c) => c.method == 'zonedSchedule').arguments as Map;
    final first = args();
    expect(first['timeZoneName'], 'Asia/Shanghai');
    expect(first['scheduledDateTime'], startsWith('${localDay(day)}T10:20:00'));
    final details = first['platformSpecifics'] as Map;
    expect(details['channelId'], 'training_plans_v2');
    expect(details['importance'], 4);
    expect(details['priority'], 1);
    expect(details['scheduleMode'], 'exactAllowWhileIdle');
    await reminders.sync(store);
    expect(args()['id'], first['id']);
    exact = false;
    await reminders.sync(store);
    expect(
      (args()['platformSpecifics'] as Map)['scheduleMode'],
      'inexactAllowWhileIdle',
    );
    pending = [
      {'id': first['id'], 'title': 'test', 'body': 'test', 'payload': 'one'},
    ];
    await store.savePlan({...plan, 'paused': true});
    calls.clear();
    await reminders.sync(store);
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    expect(calls.where((c) => c.method == 'cancel').single.arguments, {
      'id': first['id'],
      'tag': null,
    });
    expect(calls.where((c) => c.method == 'cancelAll'), isEmpty);
    permission = false;
    expect(await reminders.request(), isFalse);
  });
}
