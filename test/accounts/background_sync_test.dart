import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/task_engine_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('headless open preserves an unfinished training byte-for-byte and is read-only', () async {
    final directory = await Directory.systemTemp.createTemp(
      'account-background-',
    );
    final foreground = PracticeRepository();
    await foreground.open(directory.path, 'en');
    final engine = fixture.create(ManualClock());
    await foreground.create(
      engine,
      {
        'schema_version': 1,
        'platform': 'ANDROID',
        'os_version': 'test',
        'app_version': 'test',
        'build_id': 'test',
        'device_model': 'test',
        'device_local_id': 'test',
        'clock_source': 'DART_RECEIPT',
        'layout_id': 'test',
        'audio_backend': 'SOUNDPOOL',
        'audio_route_category': 'MUTED',
        'sound_enabled': false,
        'screen_reader_active': false,
        'app_gain_permille': 600,
        'window_width_dp': 800,
        'window_height_dp': 360,
        'text_scale_permille': 1000,
      },
      null,
      'Asia/Shanghai',
    );
    final original = await foreground.db.query('sessions');
    final events = await foreground.db.query('events', orderBy: 'seq');
    final profiles = await foreground.db.query('profiles');
    await foreground.db.close();
    final reader = PracticeRepository();
    try {
      await reader.openForBackground(directory.path);
      expect(await reader.db.query('sessions'), original);
      expect(await reader.db.query('events', orderBy: 'seq'), events);
      expect(await reader.db.query('profiles'), profiles);
      expect(reader.profile['profile_id'], profiles.single['profile_id']);
      await expectLater(
        reader.db.rawDelete('DELETE FROM sessions'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        await Directory('${directory.path}/migration-backups').exists(),
        isFalse,
      );
    } finally {
      if (reader.db.isOpen) await reader.db.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'headless open does not create a new database or migrate an old one',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'account-background-old-',
      );
      final repository = PracticeRepository();
      try {
        await expectLater(
          repository.openForBackground(directory.path),
          throwsStateError,
        );
        expect(await File('${directory.path}/practice.db').exists(), isFalse);
        final old = await openDatabase(
          '${directory.path}/practice.db',
          version: 3,
        );
        await old.close();
        await expectLater(
          repository.openForBackground(directory.path),
          throwsStateError,
        );
        final check = await openDatabase(
          '${directory.path}/practice.db',
          readOnly: true,
          singleInstance: false,
        );
        expect(await check.getVersion(), 3);
        await check.close();
        expect(
          await Directory('${directory.path}/migration-backups').exists(),
          isFalse,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
