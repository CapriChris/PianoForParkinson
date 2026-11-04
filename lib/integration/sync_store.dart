/// Sidecar synchronization DB: the validated local practice.db schema v4 and
/// historical practice records are never mutated by networking.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class SyncStore {
  SyncStore({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  late Database db;
  Future<void> open(String directory) async {
    db = await openDatabase(
      '$directory/pd_cloud_sync.db',
      version: 4,
      singleInstance: false,
      onCreate: (db, _) async {
        await _captureSchema(db);
        await db.execute(
          'CREATE TABLE synced_records (record_type TEXT NOT NULL, record_id TEXT NOT NULL, patient_id TEXT NOT NULL, completed_ms INTEGER NOT NULL, PRIMARY KEY(record_type,record_id,patient_id))',
        );
        await db.execute(
          'CREATE TABLE kv (name TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE cloud_patients (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE cloud_staff (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE cloud_records (patient_id TEXT NOT NULL, kind TEXT NOT NULL, record_id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(patient_id,kind,record_id))',
        );
        await _createOutbox(db);
        await _upgradeOrdinarySync(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 3) {
          await _captureSchema(db);
          await _createOutbox(db);
        }
        if (oldVersion < 4) await _upgradeOrdinarySync(db);
      },
    );
  }

  static Future<void> _captureSchema(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS training_captures (capture_id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, record_id TEXT, payload TEXT NOT NULL)',
  );

  static Future<void> _upgradeOrdinarySync(Database db) async {
    await db.execute(
      'ALTER TABLE sync_outbox ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE sync_outbox ADD COLUMN next_retry_ms INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE sync_outbox ADD COLUMN last_retry_status INTEGER',
    );
    await db.execute('ALTER TABLE sync_outbox ADD COLUMN server_ack_id TEXT');
    await db.execute('ALTER TABLE sync_outbox ADD COLUMN server_ack_hash TEXT');
    await db.execute(
      'CREATE TABLE scoped_cloud (scope TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(scope,kind,id))',
    );
    // Older downloads had no account or binding scope. Do not migrate them.
    for (final table in ['cloud_records', 'cloud_patients', 'cloud_staff']) {
      final exists = await db.rawQuery(
        'SELECT 1 FROM sqlite_master WHERE type=? AND name=?',
        ['table', table],
      );
      if (exists.isNotEmpty) await db.delete(table);
    }
  }

  Future<void> applyPage(
    String scope,
    Map<String, dynamic> page,
    bool Function() current,
  ) => db.transaction((tx) async {
    if (!current()) return;
    final cursor = page['next_cursor'] as String;
    for (final raw in page['items'] as List) {
      final item = raw as Map;
      final kind = item['kind'] as String, id = item['id'] as String;
      if (item['deleted'] == true) {
        await tx.delete(
          'scoped_cloud',
          where: 'scope=? AND kind=? AND id=?',
          whereArgs: [scope, kind, id],
        );
      } else {
        await tx.insert('scoped_cloud', {
          'scope': scope,
          'kind': kind,
          'id': id,
          'payload': jsonEncode(item['data']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await tx.insert('kv', {
      'name': 'cursor:$scope',
      'value': cursor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> clearScope(String scope) => db.transaction((tx) async {
    await tx.delete('scoped_cloud', where: 'scope=?', whereArgs: [scope]);
    await tx.delete('kv', where: 'name=?', whereArgs: ['cursor:$scope']);
  });

  Future<List<Map<String, dynamic>>> readScope(String scope) async => [
    for (final row in await db.query(
      'scoped_cloud',
      where: 'scope=?',
      whereArgs: [scope],
      orderBy: 'rowid DESC',
      limit: 300,
    ))
      {'kind': row['kind'], 'data': jsonDecode(row['payload'] as String)},
  ];

  static Future<void> _createOutbox(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sync_outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL, body TEXT, error_status INTEGER, UNIQUE(scope,kind,source))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS plan_revisions (scope TEXT NOT NULL, plan TEXT NOT NULL, fingerprint TEXT NOT NULL, revision INTEGER NOT NULL, PRIMARY KEY(scope,plan))',
    );
  }

  Future<bool> known(String scope, String kind, String source) async =>
      (await db.query(
        'sync_outbox',
        columns: ['seq'],
        where: 'scope=? AND kind=? AND source=?',
        whereArgs: [scope, kind, source],
        limit: 1,
      )).isNotEmpty;

  Future<void> enqueue(String scope, Map<String, dynamic> body) async {
    await db.insert(
      'sync_outbox',
      _entry(scope, body),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Map<String, Object?> _entry(String scope, Map<String, dynamic> body) => {
    'scope': scope,
    'kind': body['record_type'],
    'source': body['source_record_id'],
    'body': jsonEncode(body),
  };

  Future<void> enqueuePlan(
    String scope,
    String plan,
    String fingerprint,
    Map<String, dynamic> body,
  ) async {
    await db.transaction((tx) async {
      final previous = await tx.query(
        'plan_revisions',
        where: 'scope=? AND plan=?',
        whereArgs: [scope, plan],
      );
      if (previous.isNotEmpty &&
          previous.single['fingerprint'] == fingerprint) {
        return;
      }
      final revision = previous.isEmpty
          ? 1
          : (previous.single['revision'] as int) + 1;
      final source = '$plan:r$revision:${fingerprint.substring(0, 24)}';
      final payload = Map<String, dynamic>.from(body['payload'] as Map);
      await tx.insert(
        'sync_outbox',
        _entry(scope, {
          ...body,
          'source_record_id': source,
          'payload': {...payload, 'snapshot_revision': revision},
        }),
      );
      await tx.insert('plan_revisions', {
        'scope': scope,
        'plan': plan,
        'fingerprint': fingerprint,
        'revision': revision,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, Object?>>> pending(String scope) async {
    final now = _now().millisecondsSinceEpoch;
    final hold = int.tryParse(await get('upload-hold:$scope') ?? '') ?? 0;
    if (hold > now) return [];
    return db.query(
      'sync_outbox',
      where: 'scope=? AND body IS NOT NULL AND error_status IS NULL AND next_retry_ms<=?',
      whereArgs: [scope, now],
      orderBy: 'seq',
      limit: 60,
    );
  }

  Future<void> postpone(
    String scope,
    int seq,
    int attempts,
    int status,
    Duration delay,
  ) async {
    final until = _now().add(delay).millisecondsSinceEpoch;
    await db.transaction((tx) async {
      await tx.update(
        'sync_outbox',
        {
          'retry_count': attempts,
          'last_retry_status': status,
          'next_retry_ms': until,
        },
        where: 'scope=? AND seq=?',
        whereArgs: [scope, seq],
      );
      if (status == 429) {
        await tx.insert('kv', {
          'name': 'upload-hold:$scope',
          'value': '$until',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> queuedCount(String scope) async =>
      (await db.rawQuery(
            'SELECT COUNT(*) AS n FROM sync_outbox WHERE scope=? AND body IS NOT NULL AND error_status IS NULL',
            [scope],
          )).single['n']
          as int;

  Future<void> reject(String scope, int seq, int status) async {
    await db.update(
      'sync_outbox',
      {'error_status': status},
      where: 'scope=? AND seq=?',
      whereArgs: [scope, seq],
    );
  }

  Future<int> rejectedCount(String scope) async =>
      (await db.rawQuery(
            'SELECT count(*) AS count FROM sync_outbox WHERE scope=? AND error_status IS NOT NULL',
            [scope],
          )).single['count']
          as int;

  Future<void> acknowledge(
    String scope,
    int seq, {
    Map<String, dynamic>? receipt,
  }) async {
    await db.update(
      'sync_outbox',
      {
        'body': null,
        'server_ack_id': receipt?['id'],
        'server_ack_hash': receipt?['payload_sha256'],
      },
      where: 'scope=? AND seq=?',
      whereArgs: [scope, seq],
    );
  }

  Future<void> put(String key, String value) async {
    await db.insert('kv', {
      'name': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> get(String key) async {
    final row = await db.query('kv', where: 'name=?', whereArgs: [key]);
    return row.isEmpty ? null : row.first['value'] as String;
  }

  Future<void> rememberBootstrap(Map<String, dynamic> payload) async {
    await db.transaction((tx) async {
      for (final key in ['patients', 'staff']) {
        final table = key == 'patients' ? 'cloud_patients' : 'cloud_staff';
        for (final entry in (payload[key] as List? ?? const [])) {
          final object = Map<String, dynamic>.from(entry as Map);
          await tx.insert(table, {
            'id': object['id'],
            'payload': jsonEncode(object),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<int> staffCount() async => (await db.query('cloud_staff')).length;
  Future<List<Map<String, dynamic>>> patients() async =>
      (await db.query('cloud_patients', orderBy: 'id'))
          .map(
            (row) => Map<String, dynamic>.from(
              jsonDecode(row['payload'] as String) as Map,
            ),
          )
          .toList();
  Future<void> rememberPatientData(Map<String, dynamic> snapshot) async {
    final pid = snapshot['patient_id'] as String;
    final categories = Map<String, dynamic>.from(snapshot['categories'] as Map);
    await db.transaction((tx) async {
      for (final entry in categories.entries) {
        for (final value in (entry.value as List)) {
          final item = Map<String, dynamic>.from(value as Map);
          await tx.insert('cloud_records', {
            'patient_id': pid,
            'kind': entry.key,
            'record_id': '${item['id']}',
            'payload': jsonEncode(item),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> patientRecords(String patientId) async =>
      (await db.query(
            'cloud_records',
            where: 'patient_id=?',
            whereArgs: [patientId],
            limit: 300,
            orderBy: 'kind,record_id',
          ))
          .map(
            (row) => {
              'kind': row['kind'],
              'data': jsonDecode(row['payload'] as String),
            },
          )
          .toList();

  Future<bool> isSynced(String type, String id, String patientId) async =>
      (await db.query(
        'synced_records',
        where: 'record_type=? AND record_id=? AND patient_id=?',
        whereArgs: [type, id, patientId],
      )).isNotEmpty;
  Future<void> markSynced(String type, String id, String patientId) async {
    await db.insert('synced_records', {
      'record_type': type,
      'record_id': id,
      'patient_id': patientId,
      'completed_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
