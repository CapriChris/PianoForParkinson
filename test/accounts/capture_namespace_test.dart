import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/integration/training_capture.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('vault cleanup and reads carry the active account namespace', () async {
    final root = await Directory.systemTemp.createTemp('qin-vault-scope-');
    final calls = <MethodCall>[];
    const channel = MethodChannel('qin/capture-vault/v1');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    try {
      for (final digit in ['a', 'b']) {
        final scope = 'account-${List.filled(64, digit).join()}';
        final directory = await Directory('${root.path}/$scope').create();
        final repository = PracticeRepository()
          ..db = await databaseFactoryFfi.openDatabase(
            '${directory.path}/practice.db',
          );
        final service = TrainingCaptureService(repository);
        await service.vault<void>('cleanup', {
          'known_ids': ['owned-capture'],
        });
        await service.vault<void>('readChunk', {'capture_id': 'owned-capture'});
        for (final call in calls.skip(calls.length - 2)) {
          expect(call.arguments['owner_scope'], scope);
        }
        service.dispose();
        await repository.db.close();
      }
      expect(
        calls[0].arguments['owner_scope'],
        isNot(calls[2].arguments['owner_scope']),
      );
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await root.delete(recursive: true);
    }
  });
}
