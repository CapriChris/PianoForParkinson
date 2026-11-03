/// Sidecar synchronization DB: the validated local practice.db schema v4 and
/// historical practice records are never mutated by networking.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class SyncStore {
  late Database db;
  Future<void> open(String directory) async {
    db = await openDatabase(
      '$directory/pd_cloud_sync.db',
      version: 1,
      onCreate: (db, _) async {
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
      },
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
