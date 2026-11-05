import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/contracts.dart';

/// Local chat history, isolated from the validated practice database.
class AssistantConversationStore {
  Database? _db;
  Object? _openError;
  Future<void> _writes = Future.value();
  final _memory = <String, Json>{};

  Future<void> open(String directory) async {
    try {
      _db = await openDatabase(
        '$directory/pd_assistant_chats.db',
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE conversations (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, updated_ms INTEGER NOT NULL, body TEXT NOT NULL)',
        ),
      );
      _openError = null;
    } catch (error) {
      _openError = error;
    }
  }

  void _check() {
    if (_openError != null) throw StateError('Chat storage is unavailable');
  }

  Future<List<Json>> list(String profileId) async {
    _check();
    final db = _db;
    final rows = db == null
        ? _memory.values.where((row) => row['profile_id'] == profileId).toList()
        : (await db.query(
            'conversations',
            where: 'profile_id=?',
            whereArgs: [profileId],
            orderBy: 'updated_ms DESC, id',
          )).map((row) => jsonDecode(row['body'] as String) as Json).toList();
    rows.sort(
      (a, b) => (b['updated_ms'] as int).compareTo(a['updated_ms'] as int),
    );
    return rows;
  }

  Future<void> save(Json conversation) async {
    _check();
    final body = jsonEncode(conversation);
    final snapshot = jsonDecode(body) as Json;
    final write = _writes.catchError((_) {}).then((_) async {
      if (_db == null) {
        _memory[snapshot['id'] as String] = snapshot;
      } else {
        await _db!.insert('conversations', {
          'id': snapshot['id'],
          'profile_id': snapshot['profile_id'],
          'updated_ms': snapshot['updated_ms'],
          'body': body,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _writes = write;
    return write;
  }

  Future<void> delete(String profileId, String id) async {
    _check();
    await _writes.catchError((_) {});
    if (_db == null) {
      if (_memory[id]?['profile_id'] == profileId) _memory.remove(id);
      return;
    }
    await _db!.delete(
      'conversations',
      where: 'profile_id=? AND id=?',
      whereArgs: [profileId, id],
    );
  }

  Future<void> close() async {
    await _writes.catchError((_) {});
    await _db?.close();
  }
}
