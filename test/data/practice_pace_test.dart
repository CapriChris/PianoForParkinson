import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:piano_practice/data/content_repository.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/domain/practice_pace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'pace persists independently of mode and preserves previous difficulty',
    () async {
      final directory = await Directory.systemTemp.createTemp('piano-pace-');
      final r = PracticeRepository();
      await r.open(directory.path, 'en');
      addTearDown(() async {
        await r.db.close();
        await directory.delete(recursive: true);
      });
      final content = ContentRepository();
      await content.load();
      final base = content.config,
          comfort = practicePace(content.config, 'COMFORT');
      await r.settingsUpdate(
        mode: 'CHALLENGE',
        settings: {...r.settings, 'practice_pace': 'STANDARD'},
      );
      await r.reload();
      expect(r.settings['practice_pace'], 'STANDARD');
      expect(r.profile['mode'], 'CHALLENGE');
      final state = {
        'profile_id': r.profile['profile_id'],
        'task_id': 'G1_MEMORY',
        'mode': 'CHALLENGE',
        'parameter_profile_version': base.json['version'],
        'level': 4,
        'updated_utc_ms': 123,
      };
      await r.db.insert('profile_task_state', state);
      expect(await r.level('G1_MEMORY', comfort, fallback: base), 4);
      await r.db.insert('profile_task_state', {
        ...state,
        'parameter_profile_version': comfort.json['version'],
        'level': 3,
      });
      expect(await r.level('G1_MEMORY', comfort, fallback: base), 3);
      expect(await r.level('G1_MEMORY', base), 4);
    },
  );
}
