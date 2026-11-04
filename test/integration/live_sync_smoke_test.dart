import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/integration/auto_sync.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class _LocalCa extends HttpOverrides {
  _LocalCa(String cert)
    : context = (SecurityContext()..setTrustedCertificates(cert));
  final SecurityContext context;

  @override
  HttpClient createHttpClient(SecurityContext? _) =>
      super.createHttpClient(context);
}

void main() {
  final env = Platform.environment;
  final url = env['PD_SYNC_TEST_URL'];
  ffi.sqfliteFfiInit();
  sqlite.databaseFactory = ffi.databaseFactoryFfi;
  test(
    'Flutter sends a single immutable record and receives a real Web delta over HTTPS',
    skip: url == null
        ? 'Opt-in isolated backend; see scripts/run_local_sync_smoke.ps1.'
        : false,
    () async {
      expect(Uri.parse(url!).host, '127.0.0.1');
      await HttpOverrides.runWithHttpOverrides(() async {
        final api = RemoteApi(url);
        final health = await api.request('GET', '/system/health');
        expect(health['env'], 'test');
        final user = await api.login(
          'local-sync-qa',
          env['PD_SYNC_TEST_PASSWORD']!,
        );
        final patient = await api.request(
          'POST',
          '/patients',
          data: {'name': 'Local sync QA', 'sex': 'UNKNOWN'},
        );
        final id = patient['id'] as String;
        final dir = await Directory.systemTemp.createTemp('pd-live-sync-');
        final db = await sqlite.openDatabase('${dir.path}/practice.db');
        await db.execute(
          'CREATE TABLE sessions (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        );
        await db.execute(
          'CREATE TABLE piece_performances (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        );
        for (final sql in DatabaseSafety.migration4.split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
        final repo = PracticeRepository()
          ..db = db
          ..profile = {'profile_id': 'qa-profile'};
        final updates = ValueNotifier(0);
        final sync = AutoSync(repo, updates, () => true);
        final schedule = TrainingScheduleRepository(db, 'qa-profile');
        try {
          await schedule.saveDance({
            'session_id': 'unbound-history',
            'started_utc_ms': DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
            'active_ms': 30000,
            'covered_ms': 30000,
            'confirmed': true,
          });
          await sync.signIn(
            api,
            user['id'] as String,
            'qa-device',
            'qa-profile',
          );
          final bind = await api.bindPatient('qa-device', 'qa-profile', id);
          await sync.setBinding(id, bind['binding_id'] as String);
          await sync.sync();
          final now = DateTime.now();
          await schedule.savePlan({
            'id': 'qa-plan',
            'title': 'QA twice',
            'kind': 'dance',
            'target_type': 'count',
            'target': 2,
            'start': localDay(now),
            'end': null,
            'days': [],
            'paused': false,
          });
          for (final ident in ['dance-one', 'dance-two']) {
            await schedule.saveDance({
              'session_id': ident,
              'started_utc_ms': now.millisecondsSinceEpoch,
              'active_ms': 30000,
              'covered_ms': 30000,
              'confirmed': true,
            });
            updates.value++;
            expect((await sync.sync()).errors, isEmpty);
          }
          expect((await sync.sync()).uploaded, 0);
          final records = await api.request(
            'GET',
            '/integration/v1/records',
            query: {'patient_id': id, 'record_type': 'DANCE_SESSION'},
          );
          expect(
            (records['items'] as List)
                .where((r) => r['record_type'] == 'DANCE_SESSION')
                .map((r) => r['source_record_id']),
            unorderedEquals(['dance-one', 'dance-two']),
          );
          final plans = await api.request(
            'GET',
            '/integration/v1/plans',
            query: {'patient_id': id, 'on_date': localDay(now)},
          );
          final latest = (plans['items'] as List).single;
          expect(latest['progress']['completed_units'], 2);
          expect(latest['progress']['target'], 2);
          final assessment = await api.request(
            'POST',
            '/patients/$id/assessment-sessions',
            data: {'session_type': 'MICRO_EXPRESSION_ONLY'},
          );
          await sync.sync();
          expect(
            sync.cloud.value.any(
              (row) =>
                  row['kind'] == 'assessment_sessions' &&
                  row['data']['id'] == assessment['id'],
            ),
            isTrue,
          );
          await api.request(
            'DELETE',
            '/integration/v1/bindings/${bind['binding_id']}',
          );
          await expectLater(
            sync.sync(),
            throwsA(
              isA<RemoteApiException>().having((e) => e.status, 'status', 403),
            ),
          );
          expect(sync.cloud.value, isEmpty);
        } finally {
          final store = await sync.store();
          sync.close();
          updates.dispose();
          await store.db.close();
          await db.close();
        }
      }, _LocalCa(env['PD_SYNC_TEST_CERT']!));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
