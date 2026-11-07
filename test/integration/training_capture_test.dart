import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:piano_practice/integration/sync_store.dart';
import 'package:piano_practice/integration/training_capture.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class CaptureApi extends RemoteApi {
  CaptureApi() : super('https://example.com/api');
  @override
  bool get signedIn => true;
  final calls = <String>[];
  bool supported = true;
  bool completed = false;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    calls.add('$method $path');
    if (path.endsWith('capabilities')) {
      return {'face_recordings_ready': supported, 'face_model_ready': true};
    }
    if (path.endsWith('/complete')) {
      completed = true;
      return {'status': 'PROCESSING'};
    }
    return {
      'recording_id': 'remote-id',
      'status': 'PROCESSING',
      'upload_complete': true,
    };
  }
}

class CaptureCamera extends CameraPlatform {
  final calls = <String>[];
  final errors = StreamController<CameraErrorEvent>.broadcast();
  bool? audio;
  String? source;
  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    audio = mediaSettings.enableAudio;
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        const CameraInitializedEvent(
          1,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    calls.add('start');
  }

  @override
  Future<void> pauseVideoRecording(int cameraId) async {
    calls.add('pause');
  }

  @override
  Future<void> resumeVideoRecording(int cameraId) async {
    calls.add('resume');
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    calls.add('stop');
    return XFile(source!);
  }

  @override
  Future<void> dispose(int cameraId) async {
    calls.add('dispose');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late PracticeRepository repository;
  late TrainingCaptureService service;
  late CaptureApi api;
  late CaptureCamera camera;
  late CameraPlatform oldCamera;
  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('qin-capture-test-');
    repository = PracticeRepository()
      ..db = await databaseFactoryFfi.openDatabase(
        '${directory.path}/practice.db',
      )
      ..profile = {
        'profile_id': 'test-profile',
        'settings_json': jsonEncode({'device_local_id': 'test-device'}),
      };
    service = TrainingCaptureService(repository);
    api = CaptureApi();
    service.connect(api, 'operator');
    camera = CaptureCamera();
    oldCamera = CameraPlatform.instance;
    CameraPlatform.instance = camera;
    final source = File('${directory.path}/source.mp4');
    await source.writeAsBytes([1, 2, 3]);
    camera.source = source.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('qin/capture-vault/v1'), (
          call,
        ) async {
          if (call.method == 'space') {
            return {'free_bytes': 2 * 1024 * 1024 * 1024, 'used_bytes': 0};
          }
          if (call.method == 'metered') return false;
          if (call.method == 'seal') {
            return {
              'file_id': (call.arguments as Map)['file_id'],
              'size_bytes': 3,
              'duration_ms': 2000,
              'chunk_count': 1,
              'sha256': 'a' * 64,
              'mime_type': 'video/mp4',
            };
          }
          return null;
        });
    await service.open();
    service.bind('patient', 'binding');
  });
  tearDown(() async {
    if (service.active != null) await service.active!.discard();
    service.dispose();
    CameraPlatform.instance = oldCamera;
    await service.store.db.close();
    await repository.db.close();
    // Temporary directory was created by this fixture, never a workspace path.
    await directory.delete(recursive: true);
  });

  test(
    'preview does not record, recording is silent and pause resumes',
    () async {
      final capture = await service.prepare();
      expect(camera.calls, isEmpty);
      expect(camera.audio, false);
      await capture.setRunning(true);
      await capture.setRunning(false);
      await capture.setRunning(true);
      expect(camera.calls, ['start', 'pause', 'resume']);
      await capture.stop();
      expect(camera.calls, ['start', 'pause', 'resume', 'stop', 'dispose']);
      await capture.setRunning(true);
      expect(camera.calls.where((v) => v == 'start').length, 1);
    },
  );
  test(
    'unsupported Web service refuses recording before camera access',
    () async {
      api.supported = false;
      await expectLater(service.prepare(), throwsA(isA<RemoteApiException>()));
      expect(camera.audio, isNull);
    },
  );
  test('stopping preview never starts video', () async {
    final capture = await service.prepare();
    await capture.setRunning(false);
    expect(camera.calls, isEmpty);
    await capture.discard();
    expect(camera.calls, ['dispose']);
  });
  test(
    'background ends the file and foreground does not restart automatically',
    () async {
      final capture = await service.prepare();
      await capture.setRunning(true);
      capture.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await capture.interrupt();
      expect(camera.calls.where((c) => c == 'stop').length, 1);
      capture.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(camera.calls.where((c) => c == 'start').length, 1);
    },
  );
  test(
    'inactive notification keeps recording, real departure seals it',
    () async {
      final capture = await service.prepare();
      await capture.setRunning(true);
      capture.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(Duration.zero);
      expect(camera.calls, ['start']);
      capture.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(camera.calls, ['start']);
      capture.didChangeAppLifecycleState(AppLifecycleState.paused);
      await capture.interrupt();
      expect(camera.calls.where((c) => c == 'stop').length, 1);
      capture.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(camera.calls.where((c) => c == 'start').length, 1);
    },
  );
  test('discarded practice never creates a server recording', () async {
    final capture = await service.prepare();
    await capture.setRunning(true);
    await capture.discard();
    expect(api.calls.where((c) => c.contains('/face/recordings')), isEmpty);
    expect(capture.state, 'DELETED');
  });
  test(
    'identity changes stop collection instead of changing attribution',
    () async {
      final capture = await service.prepare();
      await capture.setRunning(true);
      service.bind('another-patient', 'another-binding');
      await capture.setRunning(true);
      expect(capture.data['patient_id'], 'patient');
      expect(capture.state, 'STOPPED');
    },
  );
  test(
    'sidecar connection can close without closing another consumer',
    () async {
      final other = SyncStore();
      await other.open(directory.path);
      await other.db.close();
      await service.store.put('test', 'alive');
      expect(await service.store.get('test'), 'alive');
    },
  );
  test('v1 sidecar migrates without changing sync history', () async {
    final folder = Directory('${directory.path}/legacy');
    await folder.create();
    final old = await databaseFactoryFfi.openDatabase(
      '${folder.path}/pd_cloud_sync.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE synced_records (record_type TEXT, record_id TEXT, patient_id TEXT, completed_ms INTEGER)',
          );
          await db.insert('synced_records', {
            'record_type': 'PIANO_SESSION',
            'record_id': 'old-record',
            'patient_id': 'patient',
            'completed_ms': 1,
          });
        },
      ),
    );
    await old.close();
    final upgraded = SyncStore();
    await upgraded.open(folder.path);
    expect(
      (await upgraded.db.query('synced_records')).single['record_id'],
      'old-record',
    );
    expect(await upgraded.db.query('training_captures'), isEmpty);
    await upgraded.db.close();
  });
}
