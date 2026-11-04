import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/integration/auto_sync.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/integration/sync_store.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class _Feed extends RemoteApi {
  _Feed() : super('https://test.example/api');
  bool authorized = true;
  int reads = 0;
  final entered = Completer<void>();
  final page = Completer<Map<String, dynamic>>();

  @override
  bool get signedIn => authorized;
  @override
  void signOut() => authorized = false;
  @override
  Future<Map<String, dynamic>> changes(
    String patient,
    String device,
    String profile,
    String? cursor,
  ) {
    reads++;
    entered.complete();
    return page.future;
  }
}

void main() {
  ffi.sqfliteFfiInit();
  sqlite.databaseFactory = ffi.databaseFactoryFfi;

  for (final hadCapture in [true, false]) {
    test(
      'sidecar v2 ${hadCapture ? 'capture' : 'outbox'} survives unification',
      () async {
        final dir = await Directory.systemTemp.createTemp('pd-sync-v2-');
        final old = await sqlite.openDatabase(
          '${dir.path}/pd_cloud_sync.db',
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE kv (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            if (hadCapture) {
              await db.execute(
                'CREATE TABLE training_captures (capture_id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, record_id TEXT, payload TEXT NOT NULL)',
              );
              await db.insert('training_captures', {
                'capture_id': 'original',
                'profile_id': 'profile',
                'payload': '{}',
              });
            } else {
              await db.execute(
                'CREATE TABLE sync_outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL, body TEXT, error_status INTEGER, UNIQUE(scope,kind,source))',
              );
              await db.insert('sync_outbox', {
                'scope': 'scope',
                'kind': 'PIANO_SESSION',
                'source': 'original',
                'body': '{}',
              });
            }
          },
        );
        await old.close();
        final store = SyncStore();
        await store.open(dir.path);
        try {
          expect(await store.db.getVersion(), 4);
          final captures = await store.db.query('training_captures');
          final pending = await store.pending('scope');
          if (hadCapture) {
            expect(captures.single['capture_id'], 'original');
            expect(pending, isEmpty);
          } else {
            expect(captures, isEmpty);
            expect(pending.single['source'], 'original');
          }
        } finally {
          await store.db.close();
          await dir.delete(recursive: true);
        }
      },
    );
  }

  test(
    'manual and automatic share one flight and logout discards a late page',
    () async {
      final dir = await Directory.systemTemp.createTemp('pd-sync-flight-');
      final database = await sqlite.openDatabase('${dir.path}/practice.db');
      for (final sql in [
        'CREATE TABLE sessions (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        'CREATE TABLE piece_performances (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        'CREATE TABLE dance_sessions (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        'CREATE TABLE training_plans (plan_id TEXT, profile_id TEXT)',
        'CREATE TABLE plan_occurrences (occurrence_id TEXT, plan_id TEXT)',
      ]) {
        await database.execute(sql);
      }
      final repository = PracticeRepository()
        ..db = database
        ..profile = {'profile_id': 'profile'};
      final update = ValueNotifier<int>(0);
      final coordinator = AutoSync(repository, update, () => true);
      final api = _Feed();
      try {
        await coordinator.signIn(api, 'staff', 'device', 'profile');
        await coordinator.setBinding('patient', 'binding');
        await api.entered.future.timeout(const Duration(seconds: 5));
        final first = coordinator.sync();
        expect(identical(first, coordinator.sync()), isTrue);
        coordinator.signOut();
        api.page.complete({
          'next_cursor': 'old',
          'has_more': false,
          'items': [
            {
              'kind': 'assessment_sessions',
              'id': 'old',
              'deleted': false,
              'data': {'id': 'old'},
            },
          ],
        });
        await first;
        expect(api.reads, 1);
        expect(coordinator.cloud.value, isEmpty);
        final store = await coordinator.store();
        expect(await store.db.query('scoped_cloud'), isEmpty);
      } finally {
        coordinator.close();
        update.dispose();
        await database.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'scoped changes and cursor are committed together and deletion is durable',
    () async {
      final dir = await Directory.systemTemp.createTemp('pd-sync-changes-');
      var store = SyncStore();
      await store.open(dir.path);
      try {
        final page = {
          'next_cursor': 'first',
          'items': [
            {
              'kind': 'assessment_sessions',
              'id': 'a',
              'deleted': false,
              'data': {'id': 'a'},
            },
          ],
        };
        await store.applyPage('a', page, () => false);
        expect(await store.get('cursor:a'), isNull);
        await store.applyPage('a', page, () => true);
        await store.db.close();
        store = SyncStore();
        await store.open(dir.path);
        expect(await store.get('cursor:a'), 'first');
        expect(await store.readScope('a'), hasLength(1));
        expect(await store.readScope('b'), isEmpty);
        await store.applyPage('a', {
          'next_cursor': 'second',
          'items': [
            {'kind': 'assessment_sessions', 'id': 'a', 'deleted': true},
          ],
        }, () => true);
        expect(await store.readScope('a'), isEmpty);
        expect(await store.get('cursor:a'), 'second');
        await store.clearScope('a');
        expect(await store.get('cursor:a'), isNull);
      } finally {
        await store.db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'HTTP 429 waits for the whole bound upload queue even after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('pd-sync-429-');
      var now = DateTime.now();
      var store = SyncStore(now: () => now);
      await store.open(dir.path);
      try {
        for (final id in ['first', 'second']) {
          await store.enqueue('a', {
            'record_type': 'PIANO_SESSION',
            'source_record_id': id,
          });
        }
        final first = (await store.pending('a')).first;
        await store.postpone(
          'a',
          first['seq'] as int,
          1,
          429,
          const Duration(seconds: 90),
        );
        await store.db.close();
        store = SyncStore(now: () => now);
        await store.open(dir.path);
        expect(await store.queuedCount('a'), 2);
        now = now.add(const Duration(seconds: 89));
        expect(await store.pending('a'), isEmpty);
        now = now.add(const Duration(seconds: 1));
        expect((await store.pending('a')).map((row) => row['source']), [
          'first',
          'second',
        ]);
      } finally {
        await store.db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
