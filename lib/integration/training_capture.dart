import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/practice_repository.dart';
import '../domain/contracts.dart';
import 'remote_api.dart';
import 'sync_store.dart';

const captureConsentVersion = 'face-capture-v1';
const captureChunkBytes = 4 * 1024 * 1024;
const captureMaxBytes = 400 * 1024 * 1024;
const captureMaxDuration = Duration(minutes: 30);
const captureRetention = Duration(days: 7);
const captureTerminalStates = {
  'SUCCESS',
  'PARTIAL_SUCCESS',
  'NO_VALID_SEGMENTS',
  'FAILED',
  'CANCELLED',
  'DELETED',
};
const _vault = MethodChannel('qin/capture-vault/v1');

/// App-owned cloud identity. Passwords and tokens are never persisted.
class TrainingCaptureService extends ChangeNotifier
    with WidgetsBindingObserver {
  TrainingCaptureService(this.repository);
  final PracticeRepository repository;
  final store = SyncStore();
  Future<void>? _opening;
  RemoteApi? api;
  String? operatorId, patientId, bindingId;
  TrainingCapture? active;
  final Map<String, Map<String, dynamic>> records = {};
  final Map<String, double> progress = {};
  bool _closed = false, _uploading = false;
  final _operations = <Future<dynamic>>{};
  Future<T> _track<T>(Future<T> Function() action) {
    final pending = Future<T>.sync(action);
    _operations.add(pending);
    unawaited(
      pending.then<void>(
        (_) {
          _operations.remove(pending);
        },
        onError: (Object _, StackTrace _) {
          _operations.remove(pending);
        },
      ),
    );
    return pending;
  }

  String? _uploadingId;
  final Map<String, bool> _waitingUploads = {};
  int _identityEpoch = 0;
  Timer? _retryTimer;
  String get profileId => repository.profile['profile_id'] as String;
  String get deviceId => repository.settings['device_local_id'] as String;
  bool get connected =>
      !_closed &&
      api?.signedIn == true &&
      patientId != null &&
      bindingId != null;
  void changed() {
    if (!_closed) notifyListeners();
  }

  Future<T?> vault<T>(String method, [Map<String, dynamic> args = const {}]) {
    final parts = File(repository.db.path).parent.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final directory = parts.isEmpty ? 'legacy' : parts.last;
    return _vault.invokeMethod<T>(method, {
      ...args,
      if (directory.startsWith('account-')) 'owner_scope': directory,
    });
  }

  Future<Map<String, dynamic>?> vaultMap(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final value = await vault<Map<dynamic, dynamic>>(method, args);
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  Future<void> open() => _opening ??= _open();
  Future<void> _open() async {
    await store.open(File(repository.db.path).parent.path);
    final rows = await store.db.query(
      'training_captures',
      where: 'profile_id=?',
      whereArgs: [profileId],
    );
    for (final row in rows) {
      final data = Map<String, dynamic>.from(
        jsonDecode(row['payload'] as String) as Map,
      );
      // Interrupted recording is never automatically submitted.
      if (data['state'] == 'RECORDING') data['state'] = 'INTERRUPTED';
      records[data['capture_id'] as String] = data;
      if (DateTime.now().millisecondsSinceEpoch - (data['created_ms'] as int) >
          captureRetention.inMilliseconds) {
        await vault<void>('delete', {'capture_id': data['capture_id']});
        data['files'] = <dynamic>[];
        data['local_expired'] = true;
      }
      await persist(data);
    }
    if (_closed) return;
    WidgetsBinding.instance.addObserver(this);
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(resumePending()),
    );
    await vault<void>('cleanup', {'known_ids': records.keys.toList()});
    changed();
  }

  void connect(RemoteApi remote, String userId) {
    _identityEpoch++;
    if (active != null && !active!.finished) unawaited(active!.stop());
    api = remote;
    operatorId = userId;
    patientId = null;
    bindingId = null;
    changed();
  }

  void bind(String patient, String binding) {
    _identityEpoch++;
    patientId = patient;
    bindingId = binding;
    changed();
    unawaited(open().then((_) => resumePending()).catchError((_) {}));
  }

  void disconnect({bool clearCredentials = true}) {
    _identityEpoch++;
    if (clearCredentials) api?.signOut();
    api = null;
    operatorId = null;
    patientId = null;
    bindingId = null;
    unawaited(active?.interrupt());
    changed();
  }

  Future<Map<String, dynamic>> capabilities() async {
    if (!connected) throw const RemoteApiException(401, '请先连接并绑定训练档案。');
    return api!.request('GET', '/integration/v1/capabilities');
  }

  Future<TrainingCapture> prepare() => _track(_prepare);
  Future<TrainingCapture> _prepare() async {
    if (_closed) throw StateError('训练档案已关闭。');
    await open();
    final identity = _identityEpoch;
    if (active != null && !active!.finished) throw StateError('已有采集正在进行。');
    final caps = await capabilities();
    if (caps['face_recordings_ready'] != true ||
        caps['face_model_ready'] != true) {
      throw const RemoteApiException(503, '训练视频分析暂不可用，请联系维护人员更新并配置 Web 服务。');
    }
    final space = await vaultMap('space');
    if ((space?['free_bytes'] as int? ?? 0) < captureMaxBytes * 2 ||
        (space?['used_bytes'] as int? ?? 0) > 1024 * 1024 * 1024) {
      throw StateError('视频存储空间不足，请先清理已保存的视频。');
    }
    final cameras = await availableCameras();
    final fronts = cameras.where(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (fronts.isEmpty) throw StateError('本设备没有可用的前置摄像头。');
    if (identity != _identityEpoch) throw StateError('训练档案已变化，请重新开启采集。');
    final capture = TrainingCapture(this, fronts.first, {
      'capture_id': uuid(),
      'profile_id': profileId,
      'device_id': deviceId,
      'patient_id': patientId,
      'binding_id': bindingId,
      'operator_id': operatorId,
      'server_origin': api!.base.toString(),
      'created_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      'consent_version': captureConsentVersion,
      'state': 'PREVIEW',
      'files': <dynamic>[],
      'timeline': <dynamic>[],
    });
    try {
      await capture.initialize();
    } catch (_) {
      await capture.discard();
      rethrow;
    }
    if (identity != _identityEpoch) {
      await capture.discard();
      throw StateError('训练档案已变化，请重新开启采集。');
    }
    active = capture;
    return capture;
  }

  Future<void> persist(Map<String, dynamic> data) =>
      _track(() => _persist(data));
  Future<void> _persist(Map<String, dynamic> data) async {
    records[data['capture_id'] as String] = data;
    await store.db.insert('training_captures', {
      'capture_id': data['capture_id'],
      'profile_id': data['profile_id'],
      'record_id': data['source_record_id'],
      'payload': jsonEncode(data),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    changed();
  }

  Map<String, dynamic>? forRecord(String recordId) {
    for (final r in records.values) {
      if (r['source_record_id'] == recordId) return r;
    }
    return null;
  }

  Future<void> recordSaved(String recordId) =>
      _track(() => _recordSaved(recordId));
  Future<void> _recordSaved(String recordId) async {
    if (_closed) return;
    if (records.isEmpty && active == null && _opening == null) return;
    try {
      await open();
    } catch (_) {
      return;
    }
    final record = forRecord(recordId);
    if (record != null) unawaited(upload(record['capture_id'] as String));
  }

  Future<String> _syncOne(
    Map<String, dynamic> capture,
    RemoteApi remote,
    bool Function() current,
  ) async {
    final id = capture['source_record_id'] as String;
    final detail = await repository.detail(id);
    if (detail == null || detail['record_unavailable'] == true) {
      throw StateError('请先成功保存本次练习。');
    }
    final payload = <String, dynamic>{'record': detail};
    if (capture['record_type'] == 'PIANO_SESSION') {
      final children = <String, dynamic>{};
      for (final table in [
        'blocks',
        'trials',
        'attempts',
        'events',
        'summaries',
        'adaptive_decisions',
      ]) {
        if (!current()) throw StateError('训练档案已关闭。');
        children[table] = await repository.db.query(
          table,
          where: 'session_id=?',
          whereArgs: [id],
        );
      }
      payload['children'] = children;
    }
    if (!current()) throw StateError('训练档案已关闭。');
    final r = await remote.syncRecord({
      'device_id': capture['device_id'],
      'local_profile_id': capture['profile_id'],
      'patient_id': capture['patient_id'],
      'source_record_id': id,
      'record_type': capture['record_type'],
      'schema_version': 'flutter-v4',
      'task_version': detail['task_version']?.toString(),
      'metric_version': detail['metric_version']?.toString(),
      'captured_at_ms': detail['started_utc_ms'],
      'payload': payload,
    });
    return r['id'] as String;
  }

  bool owns(Map<String, dynamic> row) =>
      connected &&
      row['operator_id'] == operatorId &&
      row['patient_id'] == patientId &&
      row['profile_id'] == profileId &&
      row['server_origin'] == api!.base.toString();
  Future<bool> metered() async => await vault<bool>('metered') ?? true;

  Future<void> resumePending() => _track(_resumePending);
  Future<void> _resumePending() async {
    if (_closed ||
        !connected ||
        _uploading ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      if (await metered()) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in records.values.toList()) {
        if (owns(row) &&
            {'READY', 'WAITING_NETWORK', 'RETRY'}.contains(row['state']) &&
            (row['retry_count'] as int? ?? 0) < 3 &&
            (row['next_retry_ms'] as int? ?? 0) <= now) {
          await upload(row['capture_id'] as String);
        }
      }
    } catch (_) {
      /* Pending files remain available for explicit retry. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(resumePending());
  }

  Future<void> upload(String captureId, {bool allowMobile = false}) =>
      _track(() => _upload(captureId, allowMobile: allowMobile));
  Future<void> _upload(String captureId, {bool allowMobile = false}) async {
    if (_closed) return;
    if (_uploading) {
      if (_uploadingId != captureId) _waitingUploads[captureId] = allowMobile;
      return;
    }
    final row = records[captureId];
    if (row == null ||
        row['source_record_id'] == null ||
        {
          'RECORDING',
          'PREVIEW',
          'SEALING',
          'DELETED',
          'CANCELLED',
        }.contains(row['state'])) {
      return;
    }
    if (!owns(row)) {
      row['message'] = '请登录并核验原训练档案后继续。';
      await persist(row);
      return;
    }
    _uploading = true;
    _uploadingId = captureId;
    final remote = api!, epoch = _identityEpoch;
    bool current() =>
        !_closed &&
        epoch == _identityEpoch &&
        row['state'] != 'CANCELLED' &&
        row['state'] != 'DELETED';
    try {
      if (row['remote_id'] != null && row['received'] == true) {
        await refresh(captureId);
        return;
      }
      if (row['local_expired'] == true) throw StateError('本机视频已过期，无法重新上传。');
      final isMetered = await metered();
      if (!current()) return;
      if (isMetered && !allowMobile) {
        row['state'] = 'WAITING_NETWORK';
        row['message'] = '等待 Wi-Fi，也可选择使用移动网络上传。';
        await persist(row);
        return;
      }
      final caps = await remote.request('GET', '/integration/v1/capabilities');
      if (!current()) return;
      if (caps['face_recordings_ready'] != true) {
        throw StateError('Web 服务尚未支持训练录像，请先更新服务。');
      }
      row['external_record_id'] ??= await _syncOne(row, remote, current);
      if (!current()) return;
      final files = (row['files'] as List).cast<Map<String, dynamic>>();
      if (files.isEmpty) throw StateError('本次没有可上传的视频。');
      final parent = await remote.request(
        'POST',
        '/integration/v1/face/recordings',
        data: {
          'client_capture_id': captureId,
          'device_id': row['device_id'],
          'local_profile_id': row['profile_id'],
          'patient_id': row['patient_id'],
          'external_record_id': row['external_record_id'],
          'consent_version': row['consent_version'],
          'agreed_at_ms': row['created_ms'],
          'files': files,
          'timeline': row['timeline'],
        },
      );
      if (!current()) return;
      row['remote_id'] = parent['recording_id'];
      if (parent['upload_complete'] == true) {
        row['received'] = true;
        row['remote'] = parent;
        row['state'] = parent['status'];
        await persist(row);
        await vault<void>('delete', {'capture_id': captureId});
        return;
      }
      row['state'] = 'UPLOADING';
      row.remove('message');
      await persist(row);
      final total = files.fold<int>(
        0,
        (sum, f) => sum + (f['size_bytes'] as int),
      );
      var sent = 0;
      final uploaded = Map<String, dynamic>.from(
        parent['uploaded_chunks'] as Map? ?? {},
      );
      for (final file in files) {
        final fileId = file['file_id'] as String;
        final present = (uploaded[fileId] as List? ?? []).cast<int>().toSet();
        for (var index = 0; index < file['chunk_count']; index++) {
          if (!current()) return;
          final length =
              ((file['size_bytes'] as int) - index * captureChunkBytes).clamp(
                0,
                captureChunkBytes,
              );
          if (!present.contains(index)) {
            final bytes = await vault<Uint8List>('readChunk', {
              'capture_id': captureId,
              'file_id': fileId,
              'index': index,
            });
            if (bytes == null || bytes.length != length) {
              throw StateError('视频文件校验失败。');
            }
            if (!current()) return;
            await remote.uploadCaptureChunk(
              row['remote_id'] as String,
              fileId,
              index,
              bytes,
              sha256.convert(bytes).toString(),
            );
          }
          sent += length;
          progress[captureId] = sent / total;
          changed();
        }
      }
      if (!current()) return;
      final result = await remote.request(
        'POST',
        '/integration/v1/face/recordings/${row['remote_id']}/complete',
      );
      if (!current()) return;
      row['received'] = true;
      row['state'] = result['status'];
      row['remote'] = result;
      await persist(row);
      await vault<void>('delete', {'capture_id': captureId});
    } catch (e) {
      if (current()) {
        row['state'] = e is RemoteApiException && {401, 403}.contains(e.status)
            ? 'WAITING_LOGIN'
            : 'RETRY';
        final retry = (row['retry_count'] as int? ?? 0) + 1;
        row['retry_count'] = retry;
        row['next_retry_ms'] =
            DateTime.now().millisecondsSinceEpoch +
            30000 * (1 << retry.clamp(0, 4));
        if (e is RemoteApiException && e.status == 401) remote.signOut();
        row['message'] = e is RemoteApiException
            ? e.message
            : '视频暂未提交成功，可稍后重试。';
        await persist(row);
      }
    } finally {
      _uploading = false;
      _uploadingId = null;
      changed();
      if (_waitingUploads.isNotEmpty && !_closed) {
        final next = _waitingUploads.keys.first;
        final mobile = _waitingUploads.remove(next)!;
        unawaited(upload(next, allowMobile: mobile));
      }
    }
  }

  Future<void> refresh(String id) => _track(() => _refresh(id));
  Future<void> _refresh(String id) async {
    if (_closed) return;
    final row = records[id];
    if (row == null || !owns(row) || row['remote_id'] == null) return;
    final remote = api!, epoch = _identityEpoch;
    final result = await remote.request(
      'GET',
      '/integration/v1/face/recordings/${row['remote_id']}',
    );
    if (_closed || epoch != _identityEpoch || row['state'] == 'DELETED') return;
    row['remote'] = result;
    row['state'] = result['status'];
    row.remove('message');
    await persist(row);
  }

  Future<void> retryAnalysis(String id) => _track(() => _retryAnalysis(id));
  Future<void> _retryAnalysis(String id) async {
    if (_closed) return;
    final row = records[id];
    if (row == null || !owns(row) || row['remote_id'] == null) {
      throw StateError('请连接原训练档案后重试。');
    }
    final remote = api!, epoch = _identityEpoch;
    final result = await remote.request(
      'POST',
      '/integration/v1/face/recordings/${row['remote_id']}/retry',
    );
    if (_closed || epoch != _identityEpoch || row['state'] == 'DELETED') return;
    row['remote'] = result;
    row['state'] = result['status'];
    await persist(row);
  }

  Future<void> remove(String id) => _track(() => _remove(id));
  Future<void> _remove(String id) async {
    if (_closed) return;
    final epoch = _identityEpoch;
    final row = records[id];
    if (row == null) return;
    row['state'] = 'CANCELLED';
    await persist(row);
    if (_closed || epoch != _identityEpoch) return;
    if (row['remote_id'] != null) {
      if (!owns(row)) throw StateError('请登录原训练档案后同步云端删除。');
      await api!.request(
        'DELETE',
        '/integration/v1/face/recordings/${row['remote_id']}',
      );
    }
    if (_closed || epoch != _identityEpoch) return;
    await vault<void>('delete', {'capture_id': id});
    row['state'] = 'DELETED';
    row['files'] = <dynamic>[];
    await persist(row);
  }

  Future<void>? _shutdown;
  Future<void> shutdown() => _shutdown ??= () async {
    if (!_closed) dispose();
    if (_opening == null) return;
    try {
      await _opening;
    } catch (_) {
      return;
    }
    try {
      await active?.discard();
    } catch (_) {}
    while (_operations.isNotEmpty) {
      await Future.wait(
        _operations.toList().map(
          (pending) =>
              pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ),
      );
    }
    await store.db.close();
  }();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _identityEpoch++;
    unawaited(active?.discard());
    super.dispose();
  }
}

/// One explicit consent and training attempt; camera calls are serialized.
class TrainingCapture extends ChangeNotifier with WidgetsBindingObserver {
  TrainingCapture(this.owner, this.description, this.data);
  final TrainingCaptureService owner;
  final CameraDescription description;
  final Map<String, dynamic> data;
  CameraController? camera;
  final clock = Stopwatch()..start();
  Future<void> _serial = Future.value();
  Timer? _limit, _budget;
  bool _checkingBudget = false;
  bool claimed = false, finished = false, _foreground = true;
  bool _disposed = false, _observing = false;
  String? error;
  String get id => data['capture_id'] as String;
  String get state => data['state'] as String;
  void changed() {
    if (!_disposed) notifyListeners();
    owner.changed();
  }

  Future<void> initialize() async {
    camera = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      fps: 30,
      videoBitrate: 1500000,
    );
    await camera!.initialize();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    camera!.addListener(() {
      if (camera?.value.hasError == true && state != 'STOPPED') {
        unawaited(stop());
      }
    });
    await owner.persist(data);
    changed();
  }

  Future<void> _run(Future<void> Function() action) {
    _serial = _serial.then((_) async {
      try {
        await action();
      } catch (_) {
        error = '面部采集已停止，训练可继续。';
        try {
          await _seal();
        } catch (_) {
          /* Camera resources must still be released. */
        }
        data['state'] = 'STOPPED';
        try {
          await owner.persist(data);
        } catch (_) {
          /* Practice storage is independent. */
        }
        changed();
      }
    });
    return _serial;
  }

  void event(String kind, [Map<String, dynamic>? context]) {
    (data['timeline'] as List).add({
      'event': kind,
      'elapsed_ms': clock.elapsedMilliseconds,
      ...?context,
    });
  }

  Future<void> setRunning(bool running) => _run(() async {
    if (finished || state == 'STOPPED' || !_foreground) return;
    if (!owner.owns(data)) {
      await _seal();
      data['state'] = 'STOPPED';
      changed();
      return;
    }
    if (!running && camera == null) return;
    if (camera == null) await initialize();
    final value = camera!.value;
    if (running && !value.isRecordingVideo) {
      claimed = true;
      await camera!.startVideoRecording(enablePersistentRecording: false);
      event('START', {'file_sequence': (data['files'] as List).length});
      _limit ??= Timer(captureMaxDuration, () => unawaited(stop()));
      _budget ??= Timer.periodic(const Duration(seconds: 5), (_) async {
        if (_checkingBudget ||
            finished ||
            camera?.value.isRecordingVideo != true) {
          return;
        }
        _checkingBudget = true;
        try {
          final budget = await owner.vaultMap('budget');
          final sealedBytes = (data['files'] as List).fold<int>(
            0,
            (total, file) => total + (file['size_bytes'] as int),
          );
          if ((budget?['recording_bytes'] as int? ?? 0) + sealedBytes >=
                  captureMaxBytes * .9 ||
              (budget?['free_bytes'] as int? ?? captureMaxBytes) <
                  64 * 1024 * 1024) {
            await stop();
          }
        } catch (_) {
          await stop();
        } finally {
          _checkingBudget = false;
        }
      });
    } else if (running && value.isRecordingPaused) {
      await camera!.resumeVideoRecording();
      event('RESUME');
    } else if (!running && value.isRecordingVideo && !value.isRecordingPaused) {
      await camera!.pauseVideoRecording();
      event('PAUSE');
    }
    data['state'] = running ? 'RECORDING' : 'PAUSED';
    await owner.persist(data);
    changed();
  });
  Future<void> _seal() async {
    final controller = camera;
    if (controller == null) return;
    try {
      if (controller.value.isRecordingVideo) {
        final file = await controller.stopVideoRecording();
        event('STOP');
        data['state'] = 'SEALING';
        changed();
        final fileId = uuid();
        try {
          final info = await owner.vaultMap('seal', {
            'capture_id': id,
            'file_id': fileId,
            'path': file.path,
          });
          if (info != null) {
            final files = data['files'] as List;
            files.add({...info, 'sequence': files.length});
          }
        } finally {
          final source = File(file.path);
          if (await source.exists()) await source.delete();
        }
      }
    } finally {
      camera = null;
      await controller.dispose();
    }
  }

  Future<void> interrupt() => _run(() async {
    if (finished) return;
    await _seal();
    data['state'] = 'PAUSED';
    await owner.persist(data);
    changed();
  });
  Future<void> stop() => _run(() async {
    if (finished) return;
    await _seal();
    data['state'] = 'STOPPED';
    _limit?.cancel();
    _budget?.cancel();
    await owner.persist(data);
    changed();
  });
  Future<void> finish(String recordId, String recordType) => _run(() async {
    if (finished) return;
    finished = true;
    _limit?.cancel();
    _budget?.cancel();
    data['source_record_id'] = recordId;
    data['record_type'] = recordType;
    try {
      await _seal();
    } catch (_) {
      data['capture_error'] = '部分录像未能保存';
    }
    data['state'] = (data['files'] as List).isEmpty ? 'FAILED' : 'READY';
    await owner.persist(data);
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    changed();
    _disposed = true;
    if (identical(owner.active, this)) owner.active = null;
    if (data['state'] == 'READY') unawaited(owner.upload(id));
  });
  Future<void> discard() => _run(() async {
    if (finished) return;
    finished = true;
    _limit?.cancel();
    _budget?.cancel();
    try {
      await _seal();
    } catch (_) {
      /* Discard also cleans a failed recording. */
    }
    try {
      await owner.vault<void>('delete', {'capture_id': id});
      data['state'] = 'DELETED';
      data['files'] = <dynamic>[];
      await owner.persist(data);
    } finally {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
      changed();
      _disposed = true;
      if (identical(owner.active, this)) owner.active = null;
    }
  });
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) unawaited(interrupt());
  }
}
