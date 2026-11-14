import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/training_schedule_repository.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';

enum PlanReminderAccess { ready, notificationsOff, channelQuiet, inexact }

class PlanReminders {
  PlanReminders({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  static final instance = PlanReminders();
  final DateTime Function() _clock;
  static const channelId = 'training_plans_v2';
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  void Function()? onOpen;
  Future<void> initialize() async {
    if (initialized) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('piano_icon'),
      ),
      onDidReceiveNotificationResponse: (_) => onOpen?.call(),
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            '训练计划提醒',
            description: 'Scheduled training plan reminders',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
    initialized = true;
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) onOpen?.call();
  }

  Future<bool> request() async {
    await initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    // Saving a plan must never open Android's special-access settings. Exact
    // timing is used when already allowed; otherwise sync uses normal alarms.
    if (await android.areNotificationsEnabled() != true &&
        await android.requestNotificationsPermission() != true) {
      return false;
    }
    return true;
  }

  Future<PlanReminderAccess> access() async {
    await initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (await android?.areNotificationsEnabled() != true) {
      return PlanReminderAccess.notificationsOff;
    }
    final channels = await android?.getNotificationChannels() ?? [];
    for (final channel in channels) {
      if (channel.id == channelId &&
          channel.importance.value < Importance.high.value) {
        return PlanReminderAccess.channelQuiet;
      }
    }
    return await android?.canScheduleExactNotifications() == true
        ? PlanReminderAccess.ready
        : PlanReminderAccess.inexact;
  }

  // Only an explicit tap on the setup action may open special-access settings.
  // Recheck first so an already-authorized user is never redirected again.
  Future<void> configure() async {
    final state = await access();
    if (state == PlanReminderAccess.ready) return;
    if (state == PlanReminderAccess.inexact) {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestExactAlarmsPermission();
    } else if (state == PlanReminderAccess.channelQuiet || !await request()) {
      await plugin.openAppNotificationSettings();
    }
  }

  Future<void> _pending = Future.value();
  Future<void> clearForLogout() async {
    await _pending;
    if (initialized) await plugin.cancelAll();
    onOpen = null;
  }

  Future<void> sync(TrainingScheduleRepository store, {bool chinese = true}) {
    final next = _pending.then((_) => _sync(store, chinese: chinese));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _sync(
    TrainingScheduleRepository store, {
    bool chinese = true,
  }) async {
    await initialize();
    final zone = notificationLocation(
      (await FlutterTimezone.getLocalTimezone()).identifier,
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final pending = await plugin.pendingNotificationRequests();
    final pendingById = {for (final request in pending) request.id: request};
    final allowed = await android?.areNotificationsEnabled() ?? false;
    final exact = await android?.canScheduleExactNotifications() ?? false;
    final desired = <int>{};
    final plans = await store.plans();
    final now = tz.TZDateTime.from(_clock(), zone);
    final occurrences = <({Json plan, DateTime day, tz.TZDateTime date})>[];

    for (final active in plans) {
      if (!allowed ||
          active['paused'] == true ||
          active['deleted'] == true ||
          active['reminder'] != true) {
        continue;
      }
      for (var offset = -1; offset < 30; offset++) {
        final day = DateTime(now.year, now.month, now.day + offset);
        if (!planDue(active, day)) continue;
        final date = tz.TZDateTime(
          zone,
          day.year,
          day.month,
          day.day,
          active['hour'] as int,
          active['minute'] as int,
        );
        occurrences.add((plan: active, day: day, date: date));
      }
    }

    final progress = await store.automaticProgressFor([
      for (final occurrence in occurrences)
        (plan: occurrence.plan, date: occurrence.day),
    ]);
    for (final (index, entry) in occurrences.indexed) {
      final (plan: active, :day, :date) = entry;
      final target =
          (active['target'] as int) *
          (active['target_type'] == 'minutes'
              ? Duration.millisecondsPerMinute
              : 1);
      final occurrence = '${active['id']}:${localDay(day)}';
      final id = int.parse(
        digest({'occurrence': occurrence}).substring(0, 7),
        radix: 16,
      );
      final payload = '$occurrence@${date.millisecondsSinceEpoch}';
      if (progress[index] >= target) continue;
      if (!date.isAfter(now)) {
        // An inexact alarm may still be waiting for Android to deliver it.
        // Resuming the app after its due time must not silently cancel it.
        final previous = pendingById[id];
        if (now.difference(date) <= const Duration(hours: 1) &&
            previous != null &&
            (previous.payload == payload || previous.payload == occurrence)) {
          desired.add(id);
        }
        continue;
      }
      desired.add(id);
      await plugin.zonedSchedule(
        id: id,
        scheduledDate: date,
        title: chinese ? '琴伴 · 训练计划' : 'Qinban · Training plan',
        body: chinese
            ? '该练习啦：${active['title']}'
            : 'Time to practise: ${active['title']}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            '训练计划提醒',
            channelDescription: 'Scheduled training plan reminders',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.private,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
    for (final notification in pending) {
      if (!desired.contains(notification.id)) {
        await plugin.cancel(id: notification.id);
      }
    }
  }
}

// Android can return a fixed GMT ID instead of an IANA region name.
tz.Location notificationLocation(String identifier) {
  if (identifier == 'GMT' || identifier == 'UTC') return tz.UTC;
  final fixed = RegExp(r'^(?:GMT|UTC)([+-])(\d{1,2}):?(\d{2})?$')
      .firstMatch(identifier);
  if (fixed != null) {
    final hours = int.parse(fixed[2]!), minutes = int.parse(fixed[3] ?? '0');
    if (hours > 23 || minutes > 59) throw ArgumentError.value(identifier);
    final offset = Duration(
      minutes: (hours * 60 + minutes) * (fixed[1] == '-' ? -1 : 1),
    );
    final name =
        'GMT${fixed[1]}${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    return tz.Location(name, [-8640000000000000], [0], [
      tz.TimeZone(offset, isDst: false, abbreviation: name),
    ]);
  }
  return tz.getLocation(identifier);
}
