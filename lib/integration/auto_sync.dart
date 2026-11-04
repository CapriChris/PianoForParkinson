import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/practice_repository.dart';
import 'remote_api.dart';
import 'sync_service.dart';
import 'sync_store.dart';

/// Foreground-only, app-owned session. Credentials and downloaded snapshots are
/// never written to the outbox. The database retains only queued uploads and ACKs.
class AutoSync {
  AutoSync(this.repository, this.trainingUpdates, this.canRun) {
    trainingUpdates.addListener(trigger);
  }
  final PracticeRepository repository;
  final ValueListenable<int> trainingUpdates;
  final bool Function() canRun;
  final message = ValueNotifier<String>('');
  Future<SyncStore>? _store;
  Future<SyncOutcome>? _flight;
  Timer? _timer;
  bool foreground = true, enabled = false, _closed = false;
  RemoteApi? remote;
  String? patient, profile, device, _identity;

  Future<SyncStore> store() => _store ??= _open();
  Future<SyncStore> _open() async {
    final s = SyncStore();
    await s.open(File(repository.db.path).parent.path);
    return s;
  }

  Future<void> signIn(
    RemoteApi api,
    String account,
    String deviceId,
    String profileId,
  ) async {
    signOut();
    await _flight?.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    if (_closed) return;
    final s = await store();
    if (_closed) return;
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([api.base.toString(), account, deviceId, profileId]),
          ),
        )
        .toString();
    final bound = await s.get('binding:$key');
    final auto = await s.get('auto:$key') == 'true';
    if (_closed) return;
    _identity = key;
    remote = api;
    device = deviceId;
    profile = profileId;
    patient = bound;
    enabled = auto && bound != null;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => trigger());
  }

  Future<void> setBinding(String id) async {
    final key = _identity;
    if (key == null || remote?.signedIn != true) throw StateError('请先登录。');
    if (patient != null && patient != id) throw StateError('不能自动更换已绑定患者。');
    await (await store()).put('binding:$key', id);
    if (_identity == key) patient = id;
  }

  Future<void> setEnabled(bool value) async {
    final key = _identity;
    if (key == null || patient == null || remote?.signedIn != true) {
      throw StateError('请先确认患者绑定。');
    }
    await (await store()).put('auto:$key', value.toString());
    if (_identity != key) return;
    enabled = value;
    if (value) trigger();
  }

  void signOut() {
    remote?.signOut();
    remote = null;
    patient = null;
    profile = null;
    device = null;
    _identity = null;
    enabled = false;
    _timer?.cancel();
    _timer = null;
  }

  void trigger() {
    if (_closed ||
        !foreground ||
        !enabled ||
        !canRun() ||
        remote?.signedIn != true ||
        patient == null) {
      return;
    }
    unawaited(
      sync(
        automatic: true,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<SyncOutcome> sync({bool automatic = false}) {
    final api = remote,
        id = patient,
        key = _identity,
        local = profile,
        dev = device;
    if (api == null ||
        !api.signedIn ||
        id == null ||
        key == null ||
        local == null ||
        dev == null) {
      return Future.error(StateError('请先登录并确认患者绑定。'));
    }
    return _flight ??= _perform(
      api,
      id,
      key,
      local,
      dev,
      automatic,
    ).whenComplete(() => _flight = null);
  }

  Future<SyncOutcome> _perform(
    RemoteApi api,
    String id,
    String key,
    String local,
    String dev,
    bool automatic,
  ) async {
    bool current() =>
        !_closed && identical(remote, api) && api.signedIn && patient == id;
    try {
      final result = await CrossClientSync(
        repository,
        api,
        await store(),
        deviceId: dev,
        localProfileId: local,
        patientId: id,
        scope: '$key:$id',
        mayUpload: () =>
            current() &&
            repository.profile['profile_id'] == local &&
            (!automatic || (enabled && foreground && canRun())),
      ).syncAll();
      if (current()) {
        message.value = result.errors.isEmpty
            ? '同步检查完成，已上传 ${result.uploaded} 条。'
            : '已上传 ${result.uploaded} 条，未确认的记录保留待重试。';
      }
      return result;
    } on RemoteApiException catch (e) {
      if (current() && (e.status == 401 || e.status == 403)) {
        signOut();
        message.value = '登录失效或权限已撤销，请重新登录；待同步记录已保留。';
      }
      rethrow;
    }
  }

  void close() {
    _closed = true;
    trainingUpdates.removeListener(trigger);
    signOut();
    final storeFuture = _store;
    unawaited(() async {
      try {
        await _flight;
      } catch (_) {}
      try {
        if (storeFuture != null) await (await storeFuture).db.close();
      } catch (_) {}
    }());
    message.dispose();
  }
}
