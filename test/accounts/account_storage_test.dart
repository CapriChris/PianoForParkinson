import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_session.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'account_api_test.dart' show response, savedSession;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'switching accounts isolates plans and preserves each stable device ID',
    () async {
      final root = await Directory.systemTemp.createTemp('account-isolation-');
      addTearDown(() => root.delete(recursive: true));
      final a = savedSession();
      final b = AccountSession.parse({
        ...response(user: '33333333-3333-4333-8333-333333333333'),
        'device_id': 'session-b',
        'base': accountApiBase,
      });
      for (final user in [a, b]) {
        await Directory('${root.path}/${user.directory}').create();
      }
      final first = PracticeRepository();
      await first.open('${root.path}/${a.directory}', 'zh-Hans');
      final device = first.settings['device_local_id'];
      final profile = first.profile['profile_id'] as String;
      await TrainingScheduleRepository(first.db, profile).savePlan({
        'id': 'plan-a',
        'title': '账号 A 的计划',
        'kind': 'dance',
        'target_type': 'count',
        'target': 2,
        'start': '2026-11-06',
        'end': null,
        'repeat_mode': 'daily',
        'days': [],
        'hour': 10,
        'minute': 0,
        'paused': false,
        'reminder': false,
      });
      await first.db.close();
      final second = PracticeRepository();
      await second.open('${root.path}/${b.directory}', 'zh-Hans');
      expect(
        await TrainingScheduleRepository(
          second.db,
          second.profile['profile_id'] as String,
        ).plans(),
        isEmpty,
      );
      expect(second.settings['device_local_id'], isNot(device));
      await second.db.close();
      await first.open('${root.path}/${a.directory}', 'zh-Hans');
      expect(first.settings['device_local_id'], device);
      expect(
        (await TrainingScheduleRepository(
          first.db,
          profile,
        ).plans()).single['title'],
        '账号 A 的计划',
      );
      await first.db.close();
    },
  );
}
