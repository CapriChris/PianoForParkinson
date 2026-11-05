import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/assistant_conversation_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
    'chat history survives reopening and stays isolated by local profile',
    () async {
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp('piano-chat-');
      addTearDown(() => directory.delete(recursive: true));
      final store = AssistantConversationStore();
      await store.open(directory.path);
      final writes = [
        for (var i = 0; i < 3; i++)
          store.save({
            'id': 'chat',
            'profile_id': 'one',
            'updated_ms': i,
            'title': 'Conversation',
            'turns': [
              {'question': 'message-$i'},
            ],
          }),
      ];
      await Future.wait(writes);
      await store.close();
      final reopened = AssistantConversationStore();
      await reopened.open(directory.path);
      addTearDown(reopened.close);
      expect((await reopened.list('one')).single['turns'], [
        {'question': 'message-2'},
      ]);
      expect(await reopened.list('two'), isEmpty);
      await reopened.delete('two', 'chat');
      expect(await reopened.list('one'), hasLength(1));
      await reopened.delete('one', 'chat');
      expect(await reopened.list('one'), isEmpty);
    },
  );
}
