import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/platform/plan_reminders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android delivers a scheduled training reminder', (tester) async {
    expect(const bool.fromEnvironment('DANCE_FLOW_TEST_PACKAGE'), isTrue);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('训练通知验证'))),
      ),
    );
    final path =
        '${await getDatabasesPath()}/notification-qa-${DateTime.now().microsecondsSinceEpoch}.db';
    final db = await openDatabase(path);
    try {
      for (final sql in DatabaseSafety.migration4.split(';')) {
        if (sql.trim().isNotEmpty) await db.execute(sql);
      }
      final store = TrainingScheduleRepository(db, 'notification-qa');
      final service = PlanReminders();
      await service.initialize();
      final android = service.plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      expect(await android.areNotificationsEnabled(), isTrue);
      expect(await service.access(), PlanReminderAccess.inexact);
      final now = DateTime.now();
      var target = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + 1,
      );
      if (target.difference(now).inSeconds < 45) {
        target = target.add(const Duration(minutes: 1));
      }
      await store.savePlan({
        'id': 'notification-qa',
        'title': '训练通知验证',
        'kind': 'dance',
        'start': localDay(target),
        'end': null,
        'days': <int>[],
        'target_type': 'count',
        'target': 1,
        'reminder': true,
        'paused': false,
        'hour': target.hour,
        'minute': target.minute,
      });
      await service.sync(store);
      final pending = await service.plugin.pendingNotificationRequests();
      expect(pending.length, 1);
      final id = pending.single.id;
      debugPrint('REMINDER_QA_WAITING_EXACT_PERMISSION');
      final permissionDeadline = DateTime.now().add(
        const Duration(seconds: 40),
      );
      while (await android.canScheduleExactNotifications() != true &&
          DateTime.now().isBefore(permissionDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(await service.access(), PlanReminderAccess.ready);
      // Existing permission must not redirect the user to settings again.
      await service.configure();
      await service.sync(store);
      expect(
        (await service.plugin.pendingNotificationRequests()).single.id,
        id,
      );
      debugPrint('REMINDER_QA_EXACT_SCHEDULED:$id target=$target');
      final deadline = target.add(const Duration(seconds: 25));
      var delivered = false;
      while (DateTime.now().isBefore(deadline)) {
        final active = await service.plugin.getActiveNotifications();
        delivered = active.any((n) => n.id == id && n.body == '该练习啦：训练通知验证');
        if (delivered) break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      expect(
        delivered,
        isTrue,
        reason: 'The Android notification manager must contain the scheduled app notification.',
      );
      await service.plugin.cancel(id: id);
    } finally {
      await db.close();
      if (await File(path).exists()) await File(path).delete();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
