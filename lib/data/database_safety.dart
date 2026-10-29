import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../domain/contracts.dart';

class DatabaseSafety {
  static const version = 3;
  static const migration3 = '''CREATE TABLE piece_performances (
session_id TEXT PRIMARY KEY,
profile_id TEXT NOT NULL REFERENCES profiles(profile_id) ON DELETE CASCADE,
content_id TEXT NOT NULL,
started_utc_ms INTEGER NOT NULL,
ended_utc_ms INTEGER NOT NULL,
session_utc_offset_minutes INTEGER NOT NULL,
record_json TEXT NOT NULL,
record_hash TEXT NOT NULL
);
CREATE INDEX idx_piece_history ON piece_performances(profile_id,started_utc_ms DESC,session_id)''';
  static const migration2 =
      'CREATE INDEX IF NOT EXISTS idx_sessions_recommendation '
      'ON sessions(profile_id,status,ended_utc_ms,task_id,content_id)';
  String? path, backupPath;

  /// Checkpoint and close before copying, so the backup includes committed WAL.
  /// This runs before the repository opens its single writer connection.
  Future<void> prepare(String databasePath) async {
    path = databasePath;
    if (!await File(databasePath).exists()) return;
    final probe = await openDatabase(databasePath, singleInstance: false);
    try {
      final old = await probe.getVersion();
      if (old > version || old < 1) {
        throw StateError('E_SCHEMA_VERSION: original database preserved');
      }
      await verify(probe);
      if (old < version) {
        final checkpoint = await probe.rawQuery(
          'PRAGMA wal_checkpoint(TRUNCATE)',
        );
        if (checkpoint.isEmpty || checkpoint.single.values.first != 0) {
          throw StateError('E_DB_BACKUP_BUSY');
        }
        await probe.close();
        final directory = Directory(
          '${File(databasePath).parent.path}/migration-backups',
        );
        await directory.create(recursive: true);
        backupPath = '${directory.path}/practice-v$old-${uuid()}.db';
        await File(databasePath).copy(backupPath!);
        // Make the private backup standalone, including on older Android SQLite
        // versions that cannot open a WAL-mode database read-only without peers.
        final backupWriter = await openDatabase(
          backupPath!,
          singleInstance: false,
        );
        try {
          final mode = await backupWriter.rawQuery(
            'PRAGMA journal_mode=DELETE',
          );
          if (mode.isEmpty ||
              '${mode.single.values.first}'.toLowerCase() != 'delete') {
            throw StateError('E_DB_BACKUP_MODE');
          }
        } finally {
          await backupWriter.close();
        }
        final backup = await openDatabase(
          backupPath!,
          readOnly: true,
          singleInstance: false,
        );
        try {
          await verify(backup);
          if (await backup.getVersion() != old) throw StateError('E_DB_BACKUP');
        } finally {
          await backup.close();
        }
      }
    } finally {
      if (probe.isOpen) await probe.close();
    }
  }

  static Future<void> verify(DatabaseExecutor db) async {
    final quick = await db.rawQuery('PRAGMA quick_check');
    final foreign = await db.rawQuery('PRAGMA foreign_key_check');
    if (quick.isEmpty ||
        quick.any((r) => r.values.single != 'ok') ||
        foreign.isNotEmpty) {
      throw StateError('E_DB_CORRUPT: original database preserved');
    }
  }

  static Future<void> migrate(Database db, int old, int next) async {
    if (old < 1 || old >= next || next > version) {
      throw StateError('E_DB_MIGRATION_PATH');
    }
    for (var target = old + 1; target <= next; target++) {
      final sql = target == 2 ? migration2 : migration3;
      for (final statement in sql.split(';')) {
        if (statement.trim().isNotEmpty) await db.execute(statement);
      }
      await db.insert('schema_migrations', {
        'version': target,
        'applied_utc_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
        'migration_checksum': digest(sql),
      });
    }
    await verify(db);
  }

  Future<void> committed() async {
    final backup = backupPath;
    if (backup != null && await File(backup).exists()) {
      try {
        await File(backup).delete();
      } on FileSystemException {
        return;
      }
    }
    backupPath = null;
  }

  Future<Database> openReadOnly() async {
    final databasePath = path;
    if (databasePath == null || !await File(databasePath).exists()) {
      throw StateError('E_DB_UNAVAILABLE');
    }
    return openDatabase(databasePath, readOnly: true, singleInstance: false);
  }
}
