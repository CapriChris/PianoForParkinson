import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:piano_practice/integration/sync_store.dart';
import 'package:piano_practice/integration/sync_service.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';

class _Network extends RemoteApi {
  _Network() : super('https://test.example/api');
  bool offline = true;
  final attempts = <Map<String, dynamic>>[];
  final accepted = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> syncRecord(Map<String, dynamic> payload) async {
    attempts.add(payload);
    if (offline) throw const RemoteApiException(0, 'offline');
    accepted.add(payload);
    return {};
  }
}

void main() {
  ffi.sqfliteFfiInit();
  sqlite.databaseFactory = ffi.databaseFactoryFfi;

  test(
    'persisted outbox isolates account and keeps retry/revision identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pd-outbox-test-',
      );
      var store = SyncStore();
      await store.open(directory.path);
      try {
        const scope = 'server:account:device:profile:patient';
        Map<String, dynamic> body(int completed) => {
          'record_type': 'TRAINING_PLAN',
          'patient_id': 'patient',
          'payload': {
            'daily_progress': [
              {'completed_units': completed},
            ],
          },
        };
        await store.enqueuePlan(scope, 'plan', 'a' * 64, body(1));
        final queued = (await store.pending(scope)).single;
        await store.db.close();
        store = SyncStore();
        await store.open(directory.path);
        expect((await store.pending(scope)).single, queued);
        expect(await store.pending('another-account'), isEmpty);
        await store.enqueuePlan(scope, 'plan', 'a' * 64, body(1));
        expect(await store.pending(scope), hasLength(1));
        await store.enqueuePlan(scope, 'plan', 'b' * 64, body(2));
        final versions = await store.pending(scope);
        expect(versions, hasLength(2));
        expect(
          jsonDecode(
            versions.last['body'] as String,
          )['payload']['snapshot_revision'],
          2,
        );
        expect(versions.first['source'], queued['source']);
        await store.acknowledge(scope, versions.first['seq'] as int);
        expect(
          (await store.pending(scope)).single['source'],
          versions.last['source'],
        );
        // A real change back to prior content must still advance the revision.
        await store.enqueuePlan(scope, 'plan', 'a' * 64, body(1));
        final remaining = await store.pending(scope);
        expect(
          jsonDecode(
            remaining.last['body'] as String,
          )['payload']['snapshot_revision'],
          3,
        );
      } finally {
        await store.db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('sidecar upgrade from v1 preserves existing settings', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pd-outbox-upgrade-',
    );
    final old = await sqlite.openDatabase(
      '${directory.path}/pd_cloud_sync.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE kv (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.insert('kv', {
          'name': 'base_url',
          'value': 'https://test.example/api',
        });
      },
    );
    await old.close();
    final store = SyncStore();
    await store.open(directory.path);
    try {
      expect(await store.get('base_url'), 'https://test.example/api');
      await store.enqueue('scope', {
        'record_type': 'PIANO_SESSION',
        'source_record_id': 'test',
      });
      final queued = (await store.pending('scope')).single;
      await store.reject('scope', queued['seq'] as int, 409);
      expect(await store.pending('scope'), isEmpty);
      expect(await store.rejectedCount('scope'), 1);
      await store.enqueue('scope', {
        'record_type': 'PIANO_SESSION',
        'source_record_id': 'next',
      });
      expect((await store.pending('scope')).single['source'], 'next');
    } finally {
      await store.db.close();
      await directory.delete(recursive: true);
    }
  });
  test(
    'offline dance completion replays revisions once after recovery',
    () async {
      final dir = await Directory.systemTemp.createTemp('pd-dance-sync-');
      final db = await ffi.databaseFactoryFfi.openDatabase(
        ffi.inMemoryDatabasePath,
      );
      final sidecar = SyncStore();
      await sidecar.open(dir.path);
      try {
        await db.execute(
          'CREATE TABLE sessions (session_id TEXT, profile_id TEXT)',
        );
        await db.execute(
          'CREATE TABLE piece_performances (session_id TEXT, profile_id TEXT)',
        );
        for (final sql in DatabaseSafety.migration4.split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
        final repo = PracticeRepository()
          ..db = db
          ..profile = {'profile_id': 'p'};
        final schedule = TrainingScheduleRepository(db, 'p');
        final day = DateTime.now();
        await schedule.savePlan({
          'id': 'plan',
          'title': '123',
          'kind': 'dance',
          'target_type': 'count',
          'target': 2,
          'start': localDay(day),
          'end': null,
          'days': [],
          'paused': false,
        });
        final record = {
          'session_id': 'first',
          'started_utc_ms': day.millisecondsSinceEpoch,
          'active_ms': 30000,
          'covered_ms': 30000,
          'confirmed': true,
        };
        final network = _Network();
        final sync = CrossClientSync(
          repo,
          network,
          sidecar,
          deviceId: 'device',
          localProfileId: 'p',
          patientId: 'patient',
          scope: 'scope',
          mayUpload: () => true,
        );
        await schedule.saveDance(record);
        expect((await sync.syncAll()).errors, isNotEmpty);
        final firstAttempt = network.attempts.single['source_record_id'];
        await schedule.saveDance({...record, 'session_id': 'second'});
        await sync.syncAll();
        expect(network.attempts.last['source_record_id'], firstAttempt);
        network.offline = false;
        final result = await sync.syncAll();
        expect(result.errors, isEmpty);
        final plans = network.accepted
            .where((r) => r['record_type'] == 'TRAINING_PLAN')
            .toList();
        expect(plans.map((r) => r['payload']['snapshot_revision']), [1, 2]);
        expect(
          plans.map(
            (r) => r['payload']['daily_progress'].single['completed_units'],
          ),
          [1, 2],
        );
        final count = network.accepted.length;
        await sync.syncAll();
        expect(network.accepted, hasLength(count));
      } finally {
        await sidecar.db.close();
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
