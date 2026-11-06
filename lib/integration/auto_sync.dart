import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/practice_repository.dart';
import 'remote_api.dart';
import 'sync_service.dart';
import 'sync_store.dart';

/// One foreground coordinator for uploads, scoped downloads and manual refresh.
class AutoSync {
  AutoSync(
    this.repository,
    this.trainingUpdates,
    this.canRun, {
    this.authorizationLost,
  }) {
    trainingUpdates.addListener(trigger);
  }
  final PracticeRepository repository;
  final ValueListenable<int> trainingUpdates;
  final bool Function() canRun;
  final void Function()? authorizationLost;
  final message = ValueNotifier<String>('');
  final cloud = ValueNotifier<List<Map<String, dynamic>>>(const []);
  Future<void>? _purge;
  Future<SyncStore>? _store;
  Future<SyncOutcome>? _flight;
  Timer? _timer;
  bool foreground = true, enabled = false, _closed = false;
  RemoteApi? remote;
  String? patient, profile, device, _identity;
  String? bindingId;
  int? _boundSince;
  Set<String> _unconfirmedPlans = {};
  bool? _feed;
  bool get legacyServer => _feed == false;
  int get unconfirmedPlanCount => _unconfirmedPlans.length;
  String? get _scope =>
      bindingId == null ? null : '$_identity:$patient:$bindingId';

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
    await _purge;
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
    final saved = await s.get('enrollment:$key');
    final auto = await s.get('auto:$key') != 'false';
    if (_closed) return;
    _identity = key;
    remote = api;
    device = deviceId;
    profile = profileId;
    if (saved != null) {
      final data = jsonDecode(saved) as Map;
      final id = data['patient'] as String;
      try {
        final link = await api.bindPatient(deviceId, profileId, id);
        if (identical(remote, api) && link['binding_id'] == data['binding']) {
          patient = id;
          bindingId = data['binding'] as String;
          _boundSince = data['start'] as int;
          _unconfirmedPlans = (data['plans'] as List).cast<String>().toSet();
          enabled = auto;
        }
      } on RemoteApiException catch (e) {
        if (e.status != 403 && e.status != 409) rethrow;
        message.value = '患者绑定已失效，请核对档案。';
      }
    }
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => trigger());
  }

  Future<void> setBinding(String id, String binding) async {
    final key = _identity;
    final api = remote;
    if (key == null || api?.signedIn != true) throw StateError('请先登录。');
    if (patient != null && patient != id) throw StateError('不能自动更换已绑定患者。');
    if (patient == id && bindingId == binding) return;
    final start = DateTime.now().millisecondsSinceEpoch;
    final plans = await repository.db.query(
      'training_plans',
      columns: ['plan_id'],
      where: 'profile_id=?',
      whereArgs: [profile],
    );
    if (!identical(api, remote) || api?.signedIn != true) return;
    await (await store()).put(
      'enrollment:$key',
      jsonEncode({
        'patient': id,
        'binding': binding,
        'start': start,
        'plans': [for (final p in plans) p['plan_id']],
      }),
    );
    if (_identity != key || !identical(api, remote) || api?.signedIn != true) {
      return;
    }
    patient = id;
    bindingId = binding;
    _boundSince = start;
    _unconfirmedPlans = {for (final p in plans) p['plan_id'] as String};
    enabled = true;
    trigger();
  }

  /// Account-owned databases contain no guest records. A cached binding can be
  /// restored offline; every upload still revalidates ownership on the server.
  Future<void> enrollAccount(
    RemoteApi api,
    String account,
    String deviceId,
    String profileId,
    String patientId,
  ) async {
    if (_closed ||
        (identical(remote, api) && patient == patientId && bindingId != null)) {
      return;
    }
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([api.base.toString(), account, deviceId, profileId]),
          ),
        )
        .toString();
    final s = await store();
    final saved = await s.get('account-binding:$key');
    String binding;
    if (saved != null) {
      final row = jsonDecode(saved) as Map;
      if (row['patient'] != patientId) throw StateError('账号档案不匹配。');
      binding = row['binding'] as String;
    } else {
      final row = await api.bindPatient(deviceId, profileId, patientId);
      if (row['patient_id'] != patientId) throw StateError('账号档案不匹配。');
      binding = row['binding_id'] as String;
      await s.put(
        'account-binding:$key',
        jsonEncode({'patient': patientId, 'binding': binding}),
      );
    }
    if (_closed || !api.signedIn) return;
    _identity = key;
    remote = api;
    device = deviceId;
    profile = profileId;
    patient = patientId;
    bindingId = binding;
    _boundSince = 0;
    _unconfirmedPlans = {};
    enabled = true;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => trigger());
    trigger();
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

  Future<void> confirmExistingPlans() async {
    final id = patient,
        binding = bindingId,
        key = _identity,
        start = _boundSince;
    final api = remote;
    if (id == null ||
        binding == null ||
        key == null ||
        start == null ||
        api?.signedIn != true) {
      throw StateError('请先确认患者绑定。');
    }
    await (await store()).put(
      'enrollment:$key',
      jsonEncode({
        'patient': id,
        'binding': binding,
        'start': start,
        'plans': <String>[],
      }),
    );
    if (identical(api, remote) && patient == id && bindingId == binding) {
      _unconfirmedPlans = {};
      trigger();
    }
  }

  void signOut() {
    final scope = _scope;
    final opened = _store;
    if (scope != null && opened != null) {
      _purge = opened.then((s) => s.clearScope(scope));
      unawaited(_purge!.catchError((Object _) {}));
    }
    remote?.signOut();
    remote = null;
    patient = null;
    profile = null;
    device = null;
    _identity = null;
    bindingId = null;
    _boundSince = null;
    _unconfirmedPlans = {};
    _feed = null;
    enabled = false;
    if (!_closed) cloud.value = [];
    _timer?.cancel();
    _timer = null;
  }

  void trigger() {
    if (!_closed &&
        remote != null &&
        (remote?.signedIn != true ||
            repository.profile['profile_id'] != profile)) {
      signOut();
      authorizationLost?.call();
      message.value = '需要重新登录；待同步记录已保留。';
      return;
    }
    if (_closed ||
        !foreground ||
        !enabled ||
        !canRun() ||
        remote?.signedIn != true ||
        patient == null) {
      return;
    }
    unawaited(
      sync(automatic: true)
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<SyncOutcome> sync({bool automatic = false, bool background = false}) {
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
    if ((!foreground && !background) || !canRun()) {
      return Future.error(StateError('训练结束后会继续同步。'));
    }
    return _flight ??= _perform(
      api,
      id,
      local,
      dev,
      automatic,
      background,
    ).whenComplete(() => _flight = null);
  }

  Future<SyncOutcome> _perform(
    RemoteApi api,
    String id,
    String local,
    String dev,
    bool automatic,
    bool background,
  ) async {
    final scope = _scope!;
    final enrolledAt = _boundSince!;
    final excludedPlans = _unconfirmedPlans;
    bool current() =>
        !_closed &&
        identical(remote, api) &&
        api.signedIn &&
        patient == id &&
        repository.profile['profile_id'] == local;
    try {
      final sidecar = await store();
      if (current()) message.value = '同步中…';
      final result = await CrossClientSync(
        repository,
        api,
        sidecar,
        deviceId: dev,
        localProfileId: local,
        patientId: id,
        scope: scope,
        boundSinceMs: enrolledAt,
        unconfirmedPlans: excludedPlans,
        mayUpload: () =>
            current() &&
            repository.profile['profile_id'] == local &&
            (foreground || background) &&
            canRun() &&
            (!automatic || enabled),
      ).syncAll();
      String? pullMessage;
      if (current() && foreground && canRun() && _feed != false) {
        try {
          await _pull(api, sidecar, scope, id, dev, local, current);
        } on RemoteApiException catch (e) {
          if (e.status == 401 || e.status == 403) rethrow;
          if (e.status == 404 || e.status == 501) {
            _feed = false;
            pullMessage = '此 Web 尚未启用历史增量同步。';
          } else {
            cloud.value = const [];
            pullMessage = '暂时无法读取云端更新。';
          }
        } catch (_) {
          if (current()) cloud.value = const [];
          pullMessage = '暂时无法读取云端更新。';
        }
      }
      if (current()) {
        final waiting = await sidecar.queuedCount(scope);
        final failed = await sidecar.rejectedCount(scope);
        if (current()) {
          message.value =
              '已上传 ${result.uploaded} 条 · 等待同步 $waiting 条 · 失败 $failed 条。'
              '${pullMessage ?? (result.errors.isEmpty ? '' : '未确认的记录保留待处理。')}';
        }
      }
      return result;
    } on RemoteApiException catch (e) {
      if (current() && (e.status == 401 || e.status == 403)) {
        signOut();
        authorizationLost?.call();
        message.value = e.status == 401
            ? '需要重新登录；待同步记录已保留。'
            : '患者绑定或权限已失效；已隐藏云端记录，待同步记录已保留。';
      }
      rethrow;
    }
  }

  Future<void> _pull(
    RemoteApi api,
    SyncStore sidecar,
    String scope,
    String id,
    String dev,
    String local,
    bool Function() current,
  ) async {
    var cursor = await sidecar.get('cursor:$scope');
    bool reset = false;
    for (
      var pages = 0;
      pages < 8 && current() && foreground && canRun();
      pages++
    ) {
      Map<String, dynamic> page;
      try {
        page = await api.changes(id, dev, local, cursor);
      } on RemoteApiException catch (e) {
        if (e.status != 409 || reset || !current()) rethrow;
        reset = true;
        await sidecar.clearScope(scope);
        cloud.value = const [];
        cursor = null;
        continue;
      }
      if (!current()) return;
      _feed = true;
      await sidecar.applyPage(scope, page, current);
      cursor = page['next_cursor'] as String;
      if (page['has_more'] != true) break;
    }
    if (!current()) return;
    final items = await sidecar.readScope(scope);
    if (current()) cloud.value = items;
  }

  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    trainingUpdates.removeListener(trigger);
    signOut();
    final storeFuture = _store;
    await () async {
      try {
        await _flight;
        await _purge;
      } catch (_) {}
      try {
        if (storeFuture != null) await (await storeFuture).db.close();
      } catch (_) {}
    }();
    message.dispose();
    cloud.dispose();
  }
}
