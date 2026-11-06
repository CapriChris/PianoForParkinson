import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/integration/sync_store.dart';
import 'package:piano_practice/integration/training_capture.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'account_api_test.dart' show savedSession;

class _UpgradeRemote extends RemoteApi {
  _UpgradeRemote(super.base);
  @override
  bool get signedIn => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  for (final connected in [true, false]) {
    test(
      'upgrade claims only verified account metadata (connected=$connected)',
      () async {
        final root = await Directory.systemTemp.createTemp('capture-upgrade-');
        final account = savedSession();
        final path = '${root.path}/${account.directory}';
        await Directory(path).create();
        final repo = PracticeRepository();
        await repo.open(path, 'zh-Hans');
        final profile = repo.profile['profile_id'];
        final sidecar = SyncStore();
        await sidecar.open(path);
        final now = DateTime.now().millisecondsSinceEpoch;
        final cases = <String, Map<String, dynamic>>{};
        for (var i = 1; i <= 7; i++) {
          final id = '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
          cases[id] = {
            'capture_id': id,
            'profile_id': profile,
            'operator_id': account.userId,
            'patient_id': account.patientId,
            'server_origin': account.base,
            'state': 'READY',
            'files': <dynamic>[],
            'created_ms': now,
          };
        }
        final ids = cases.keys.toList();
        cases[ids[1]]!['operator_id'] = 'different-user';
        cases[ids[2]]!['patient_id'] = 'different-patient';
        cases[ids[3]]!['server_origin'] = 'https://foreign.example/api';
        cases[ids[4]]!['profile_id'] = 'different-profile';
        cases[ids[5]]!['capture_id'] = '../outside';
        cases[ids[6]]!.remove('operator_id');
        // A verified expired item must be moved before the normal retention delete.
        cases[ids[0]]!['created_ms'] =
            now - const Duration(days: 8).inMilliseconds;
        for (final entry in cases.entries) {
          await sidecar.db.insert('training_captures', {
            'capture_id': entry.key,
            'profile_id': profile,
            'payload': jsonEncode(entry.value),
          });
        }
        await sidecar.db.close();
        const channel = MethodChannel('qin/capture-vault/v1');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return call.method == 'claimLegacy' ? true : null;
            });
        final service = TrainingCaptureService(repo);
        if (connected) {
          service.api = _UpgradeRemote(account.base);
          service.operatorId = account.userId;
          service.patientId = account.patientId;
          service.bindingId = 'validated-binding';
        }
        try {
          await service.open();
          final claims = calls
              .where((call) => call.method == 'claimLegacy')
              .toList();
          expect(claims.length, connected ? 1 : 0);
          if (connected) {
            expect(claims.single.arguments, {
              'owner_scope': account.directory,
              'capture_id': ids.first,
            });
            expect(
              calls.indexOf(claims.single),
              lessThan(calls.indexWhere((call) => call.method == 'delete')),
            );
          }
          expect(
            calls.every(
              (call) => call.arguments['owner_scope'] == account.directory,
            ),
            isTrue,
          );
        } finally {
          await service.shutdown();
          await repo.db.close();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await root.delete(recursive: true);
        }
      },
    );
  }
}
