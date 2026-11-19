import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/contracts.dart';
import '../integration/remote_api.dart';
import 'account_session.dart';

/// One token refresh for all concurrent requests. Credential changes are saved
/// before a new access token becomes usable; stale replies cannot revive logout.
class AccountApi extends RemoteApi {
  AccountApi({
    required this.vault,
    this.changed,
    this.invalidated,
    this.transport,
  }) : super(accountApiBase);
  final AccountVault vault;
  final void Function(AccountSession)? changed;
  final void Function()? invalidated;
  final RemoteApi? transport;
  Future<Json> _send(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) =>
      transport?.request(method, path, data: data, query: query) ??
      super.request(method, path, data: data, query: query);
  AccountSession? session;
  DateTime? _accessUntil;
  Future<void>? _refreshing;
  Future<void> _vaultWrites = Future.value();
  int _epoch = 0;
  int _profileRevision = 0;
  int _nameWriteRevision = 0;
  final profileUpdates = ValueNotifier<int>(0);
  Future<void> _clearCredential() => _vaultWrites = _vaultWrites
      .catchError((Object _) {})
      .then((_) => vault.clear());

  @override
  bool get signedIn => session != null && !session!.expired;

  Future<void> _accept(
    Json body,
    String deviceId,
    int epoch, {
    int? profileRevision,
  }) async {
    var next = AccountSession.parse({
      ...body,
      'base': base.toString(),
      'device_id': deviceId,
    });
    final old = session;
    if (old != null &&
        (old.userId != next.userId || old.patientId != next.patientId)) {
      await _queueRevocation(next);
      throw const FormatException('Account identity changed');
    }
    if (_epoch != epoch) {
      await _queueRevocation(next);
      throw const RemoteApiException(401, '登录状态已变化。');
    }
    final write = _vaultWrites.catchError((Object _) {}).then((_) async {
      if (_epoch != epoch) throw const RemoteApiException(401, '登录状态已变化。');
      if (profileRevision != null &&
          profileRevision != _profileRevision &&
          session != null) {
        next = AccountSession.parse({
          ...next.toJson(),
          'user': session!.user,
          'patient': session!.patient,
        });
      }
      await vault.write(next);
      if (_epoch != epoch) throw const RemoteApiException(401, '登录状态已变化。');
    });
    _vaultWrites = write;
    try {
      await write;
    } catch (_) {
      if (_epoch == epoch) {
        signOut();
        await _clearCredential();
        invalidated?.call();
      }
      await _queueRevocation(next);
      rethrow;
    }
    if (_epoch != epoch) {
      await _queueRevocation(next);
      throw const RemoteApiException(401, '登录状态已变化。');
    }
    session = next;
    setAccessToken(body['access_token'] as String);
    transport?.setAccessToken(body['access_token'] as String);
    _accessUntil = DateTime.now().add(
      Duration(seconds: (body['expires_in'] as int) - 30),
    );
    changed?.call(next);
    profileUpdates.value++;
    unawaited(drainRevocations());
  }

  Future<Json> authenticate(
    String username,
    String password, {
    String? displayName,
  }) async {
    final epoch = ++_epoch;
    final body = await _send(
      'POST',
      '/mobile/auth/${displayName == null ? 'login' : 'register'}',
      data: {
        'username': username.trim().toLowerCase(),
        'password': password,
        if (displayName != null) 'display_name': displayName.trim(),
        if (displayName != null) 'sync_consent_version': 'account-sync-v1',
      },
    );
    await _accept(body, uuid(), epoch);
    return body;
  }

  Future<Json> loginProviders() => _send('GET', '/mobile/auth/providers');

  Future<Json> loginIdentities() => request('GET', '/mobile/auth/identities');

  Future<Json> sendSms(String phone, {bool binding = false}) => binding
      ? request(
          'POST',
          '/mobile/auth/identities/sms/challenge',
          data: {'phone': phone},
        )
      : _send('POST', '/mobile/auth/sms/challenge', data: {'phone': phone});

  Future<Json> wechatChallenge({bool binding = false}) => binding
      ? request('POST', '/mobile/auth/identities/wechat/challenge')
      : _send('POST', '/mobile/auth/wechat/challenge');

  Future<Json> authenticateSms(String challengeId, String code) =>
      _externalLogin('sms', {'challenge_id': challengeId, 'code': code});

  Future<Json> authenticateWechat(
    String challengeId,
    String code,
    String state,
  ) => _externalLogin('wechat', {
    'challenge_id': challengeId,
    'code': code,
    'state': state,
  });

  Future<Json> _externalLogin(String provider, Json proof) async {
    final epoch = ++_epoch;
    final body = await _send(
      'POST',
      '/mobile/auth/$provider/login',
      data: {...proof, 'sync_consent_version': 'account-sync-v1'},
    );
    await _accept(body, uuid(), epoch);
    return body;
  }

  Future<Json> bindSms(String challengeId, String code) => request(
    'POST',
    '/mobile/auth/identities/sms/bind',
    data: {'challenge_id': challengeId, 'code': code},
  );

  Future<Json> bindWechat(String challengeId, String code, String state) =>
      request(
        'POST',
        '/mobile/auth/identities/wechat/bind',
        data: {'challenge_id': challengeId, 'code': code, 'state': state},
      );

  Future<void> ensureAccess({bool force = false}) async {
    if (!signedIn) throw const RemoteApiException(401, '请重新登录。');
    if (!force &&
        currentToken != null &&
        _accessUntil?.isAfter(DateTime.now()) == true) {
      return;
    }
    if (_refreshing != null) return _refreshing!;
    final epoch = _epoch;
    final current = session!;
    final profileRevision = _profileRevision;
    final next = () async {
      try {
        final body = await _send(
          'POST',
          '/mobile/auth/refresh',
          data: {'refresh_token': current.refreshToken},
        );
        await _accept(
          body,
          current.deviceId,
          epoch,
          profileRevision: profileRevision,
        );
      } on RemoteApiException catch (error) {
        if (error.status == 401 && _epoch == epoch) {
          signOut();
          await _clearCredential();
          invalidated?.call();
        }
        rethrow;
      } on FormatException {
        if (_epoch == epoch) {
          signOut();
          await _clearCredential();
          invalidated?.call();
        }
        rethrow;
      }
    }();
    _refreshing = next.whenComplete(() => _refreshing = null);
    return _refreshing!;
  }

  @override
  Future<Json> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    final epoch = _epoch;
    await ensureAccess();
    if (_epoch != epoch) throw const RemoteApiException(401, '登录状态已变化。');
    final profileRequest =
        (method == 'GET' && path == '/mobile/auth/me') ||
        (method == 'PATCH' && path == '/mobile/auth/profile');
    final revision = profileRequest ? ++_profileRevision : _profileRevision;
    final writingName = method == 'PATCH' && path == '/mobile/auth/profile';
    final nameRevision = writingName
        ? ++_nameWriteRevision
        : _nameWriteRevision;
    Json body;
    try {
      body = await _send(method, path, data: data, query: query);
    } on RemoteApiException catch (error) {
      if (error.status != 401 || _epoch != epoch) rethrow;
      // A server can revoke a session before the local access expiry.
      await ensureAccess(force: true);
      if (_epoch != epoch) throw const RemoteApiException(401, '登录状态已变化。');
      body = await _send(method, path, data: data, query: query);
    }
    if (profileRequest) {
      await _saveProfile(body, epoch, revision, writingName, nameRevision);
    }
    return body;
  }

  Future<void> refreshProfile() async {
    await request('GET', '/mobile/auth/me');
  }

  Future<void> updateName(String name, String expectedName) async {
    final value = name.trim();
    if (value.isEmpty || value.runes.length > 64) {
      throw const FormatException('姓名须为1至64个字符');
    }
    await request(
      'PATCH',
      '/mobile/auth/profile',
      data: {'display_name': value, 'expected_name': expectedName},
    );
  }

  Future<void> _saveProfile(
    Json body,
    int epoch,
    int revision,
    bool writingName,
    int nameRevision,
  ) async {
    void checkIdentity() {
      if (_epoch != epoch || session == null) {
        throw const RemoteApiException(401, '登录状态已变化。');
      }
      final user = body['user'] as Map;
      final patient = body['patient'] as Map;
      if (user['id'] != session!.userId ||
          patient['id'] != session!.patientId ||
          user['role'] != 'PATIENT' ||
          user['username'] != session!.user['username'] ||
          patient['name'] is! String ||
          (patient['name'] as String).trim().isEmpty) {
        throw const FormatException('Account identity changed');
      }
    }

    checkIdentity();
    final write = _vaultWrites.catchError((Object _) {}).then((_) async {
      checkIdentity();
      if (nameRevision != _nameWriteRevision ||
          (!writingName && revision != _profileRevision)) {
        return;
      }
      // Merge into the latest credentials; never change record partition keys.
      final next = AccountSession.parse({
        ...session!.toJson(),
        'user': body['user'],
        'patient': body['patient'],
      });
      await vault.write(next);
      checkIdentity();
      if (nameRevision != _nameWriteRevision ||
          (!writingName && revision != _profileRevision)) {
        return;
      }
      session = next;
      if (writingName) _profileRevision++;
      changed?.call(next);
      profileUpdates.value++;
    });
    _vaultWrites = write;
    await write;
  }

  @override
  Future<void> uploadCaptureChunk(
    String recordingId,
    String fileId,
    int index,
    Uint8List bytes,
    String digest,
  ) async {
    await ensureAccess();
    try {
      await super.uploadCaptureChunk(recordingId, fileId, index, bytes, digest);
    } on RemoteApiException catch (e) {
      if (e.status != 401) rethrow;
      await ensureAccess(force: true);
      await super.uploadCaptureChunk(recordingId, fileId, index, bytes, digest);
    }
  }

  Future<String> resetPassword(
    String username,
    String password,
    String recoveryCode,
  ) async {
    final body = await _send(
      'POST',
      '/mobile/auth/reset-password',
      data: {
        'username': username.trim().toLowerCase(),
        'password': password,
        'recovery_code': recoveryCode.trim(),
      },
    );
    return body['recovery_code'] as String;
  }

  Future<void> changePassword(String oldPassword, String password) async {
    await request(
      'POST',
      '/mobile/auth/change-password',
      data: {'current_password': oldPassword, 'new_password': password},
    );
  }

  Future<void> logout() async {
    final current = session;
    signOut();
    await _clearCredential();
    if (current != null) await _queueRevocation(current, waitForRemote: true);
  }

  Future<void> _queueRevocation(
    AccountSession record, {
    bool waitForRemote = false,
  }) async {
    final write = _vaultWrites.catchError((Object _) {}).then((_) async {
      final raw = await vault.readRevocations();
      final entries = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      entries.removeWhere(
        (e) =>
            !DateTime.parse(e['expires_at'] as String)
                .isAfter(DateTime.now().toUtc()),
      );
      if (!entries.any((e) => e['refresh_token'] == record.refreshToken)) {
        entries.add({
          'base': record.base,
          'refresh_token': record.refreshToken,
          'expires_at': record.refreshExpiresAt.toIso8601String(),
        });
      }
      await vault.writeRevocations(jsonEncode(entries));
    });
    _vaultWrites = write;
    await write;
    final drain = drainRevocations();
    if (waitForRemote) {
      try {
        await drain.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        /* Encrypted retry remains. */
      }
    } else {
      unawaited(drain);
    }
  }

  Future<void>? _draining;
  Future<void> drainRevocations() =>
      _draining ??= _drainRevocations().whenComplete(() => _draining = null);
  Future<void> _drainRevocations() async {
    try {
      await _vaultWrites.catchError((Object _) {});
      while (true) {
        final raw = await vault.readRevocations();
        if (raw == null) return;
        final pending = (jsonDecode(raw) as List)
            .where((item) => item['base'] == base.toString())
            .toList();
        if (pending.isEmpty) return;
        final item = pending.first;
        await _send(
          'POST',
          '/mobile/auth/logout',
          data: {'refresh_token': item['refresh_token']},
        ).timeout(const Duration(seconds: 8));
        final write = _vaultWrites.catchError((Object _) {}).then((_) async {
          final current = await vault.readRevocations();
          final entries = current == null
              ? <dynamic>[]
              : jsonDecode(current) as List;
          entries.removeWhere(
            (e) => e['refresh_token'] == item['refresh_token'],
          );
          await vault.writeRevocations(jsonEncode(entries));
        });
        _vaultWrites = write;
        await write;
      }
    } catch (_) {
      /* Keep encrypted compensation until the next login/restore. */
    }
  }

  @override
  void signOut() {
    _epoch++;
    session = null;
    _accessUntil = null;
    super.signOut();
  }
}
