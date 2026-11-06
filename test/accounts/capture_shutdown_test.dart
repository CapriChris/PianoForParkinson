import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/integration/training_capture.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SlowRepository extends PracticeRepository {
  final started = Completer<void>();
  final release = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>?> detail(String id) {
    started.complete();
    return release.future;
  }
}

class _CaptureRemote extends RemoteApi {
  _CaptureRemote() : super('https://example.com/api');
  final calls = <String>[];
  @override
  bool get signedIn => true;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    calls.add('$method $path');
    return {'face_recordings_ready': true, 'id': 'synced-record'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'account shutdown drains an upload and prevents its late identity request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qin-capture-close-',
      );
      final repo = _SlowRepository()
        ..db = await databaseFactoryFfi.openDatabase(
          '${directory.path}/practice.db',
        )
        ..profile = {
          'profile_id': 'profile',
          'settings_json': jsonEncode({'device_local_id': 'device'}),
        };
      final service = TrainingCaptureService(repo);
      final remote = _CaptureRemote();
      const channel = MethodChannel('qin/capture-vault/v1');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'metered' ? false : null,
          );
      try {
        await service.open();
        service.connect(remote, 'user-a');
        service.bind('patient-a', 'binding-a');
        service.records['capture'] = {
          'capture_id': 'capture',
          'profile_id': 'profile',
          'device_id': 'device',
          'operator_id': 'user-a',
          'patient_id': 'patient-a',
          'binding_id': 'binding-a',
          'server_origin': remote.base.toString(),
          'source_record_id': 'old-record',
          'record_type': 'DANCE',
          'state': 'READY',
          'files': <dynamic>[],
        };
        final upload = service.upload('capture', allowMobile: true);
        await repo.started.future;
        var closed = false;
        final shutdown = service.shutdown().then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, isFalse);
        expect(service.store.db.isOpen, isTrue);
        repo.release.complete({'started_utc_ms': 1});
        await upload;
        await shutdown;
        expect(remote.calls.where((c) => c.contains('/records')), isEmpty);
        expect(service.store.db.isOpen, isFalse);
      } finally {
        if (!repo.release.isCompleted) {
          repo.release.complete({'started_utc_ms': 1});
        }
        await service.shutdown();
        await repo.db.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
