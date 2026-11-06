import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../integration/remote_api.dart';
import 'secure_store.dart';

const accountApiBase = String.fromEnvironment(
  'PD_ACCOUNT_API_BASE',
  defaultValue: 'https://ccqspace.site/pd-rehab/api',
);

/// The identity can be used offline until its durable refresh session expires.
/// Passwords, recovery codes and access tokens never enter persistent storage.
class AccountSession extends ChangeNotifier {
  AccountSession({
    String baseUrl = accountApiBase,
    SecureAccountStore? store,
    RemoteApi? api,
    DateTime Function()? now,
  }) : api = api ?? RemoteApi(baseUrl),
       store = store ?? AndroidSecureAccountStore(),
       _now = now ?? DateTime.now;

  final RemoteApi api;
  final SecureAccountStore store;
  final DateTime Function() _now;
  Map<String, dynamic>? _record;
  Future<void> _writes = Future.value();
  Future<void>? _refreshing;
  int _epoch = 0;
  bool _disposed = false;
  bool restoring = false;
  bool busy = false;
  bool offline = false;
  String? error;
  bool get signedIn => _record != null && _expiry(_record!).isAfter(_now());
  Map<String, dynamic>? get user => _record == null
      ? null
      : Map<String, dynamic>.from(_record!['user'] as Map);
  Map<String, dynamic>? get patient => _record == null
      ? null
      : Map<String, dynamic>.from(_record!['patient'] as Map);
  String? get userId => user?['id'] as String?;
  String? get patientId => patient?['id'] as String?;
  String? get username => user?['username'] as String?;
  String? get displayName => user?['display_name'] as String?;
  String? get name => displayName;
  String? get hospitalNumber => patient?['hospital_number'] as String?;
  String? get accountDirectory => userId == null
      ? null
      : 'account-${sha256.convert(utf8.encode(jsonEncode([api.base.toString(), userId])))}';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _writes = _writes.then((_) async {
      try {
        result.complete(await action());
      } catch (e, stack) {
        result.completeError(e, stack);
      }
    });
    return result.future;
  }

  DateTime _expiry(Map<String, dynamic> data) =>
      DateTime.parse(data['refresh_expires_at'] as String);

  Map<String, dynamic> _validated(Map<String, dynamic> body) {
    final user = Map<String, dynamic>.from(body['user'] as Map);
    final patient = Map<String, dynamic>.from(body['patient'] as Map);
    final uuid = RegExp(
      r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
    );
    if (user['role'] != 'PATIENT' ||
        !uuid.hasMatch('${user['id']}') ||
        !uuid.hasMatch('${patient['id']}') ||
        user['username'] is! String ||
        user['display_name'] is! String ||
        patient['hospital_number'] is! String ||
        patient['name'] is! String) {
      throw const FormatException('服务端返回的账号身份无效。');
    }
    final token = body['refresh_token'];
    final expiry = DateTime.tryParse('${body['refresh_expires_at']}');
    if (token is! String ||
        token.length < 32 ||
        token.length > 256 ||
        expiry == null ||
        !expiry.isAfter(_now())) {
      throw const FormatException('服务端返回的登录会话无效。');
    }
    return {
      'base_url': api.base.toString(),
      'user': {
        'id': user['id'],
        'username': user['username'],
        'display_name': user['display_name'],
        'role': 'PATIENT',
      },
      'patient': {
        'id': patient['id'],
        'name': patient['name'],
        'hospital_number': patient['hospital_number'],
      },
      'refresh_token': token,
      'refresh_expires_at': expiry.toUtc().toIso8601String(),
    };
  }

  void _attach() {
    api.useAccountSession(
      refreshAccess: refreshAccess,
      authenticationRejected: () => _invalidate('登录已失效，请重新登录。'),
    );
  }

  Future<void> restore() async {
    final generation = ++_epoch;
    restoring = true;
    error = null;
    _changed();
    try {
      final raw = await _serial(() => store.read('session'));
      if (generation != _epoch || _disposed || raw == null) return;
      final body = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (body['base_url'] != api.base.toString()) {
        throw const FormatException('保存的服务地址与当前服务不一致。');
      }
      final record = _validated(body);
      if (generation != _epoch || _disposed) return;
      _record = record;
      _attach();
      try {
        await refreshAccess();
      } on RemoteApiException catch (e) {
        if (generation != _epoch || _disposed) return;
        if (e.status != 0 &&
            e.status != 408 &&
            e.status != 429 &&
            e.status < 500) {
          rethrow;
        }
        offline = true;
        error = '当前离线，可继续使用本机训练；联网后会验证登录并补传。';
      }
      if (generation == _epoch && !_disposed) unawaited(_drainRevocations());
    } catch (_) {
      if (generation == _epoch && !_disposed) {
        await _invalidate('无法恢复登录，请联网后重新登录。');
      }
    } finally {
      if (generation == _epoch && !_disposed) {
        restoring = false;
        _changed();
      } else if (!_disposed && _record == null) {
        restoring = false;
        _changed();
      }
    }
  }

  Future<void> _accept(
    Map<String, dynamic> body,
    int generation, {
    String? expectedUser,
    String? expectedPatient,
  }) async {
    final record = _validated(body);
    final access = body['access_token'];
    final seconds = body['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        seconds is! num ||
        seconds <= 0 ||
        seconds > 900 ||
        (expectedUser != null && record['user']['id'] != expectedUser) ||
        (expectedPatient != null &&
            record['patient']['id'] != expectedPatient)) {
      await _queueRevocation(record);
      throw const FormatException('服务端返回的登录身份或有效期无效。');
    }
    if (generation != _epoch || _disposed) {
      await _queueRevocation(record);
      throw const RemoteApiException(401, '登录操作已取消。');
    }
    try {
      await _serial(() async {
        if (generation == _epoch && !_disposed) {
          await store.write('session', jsonEncode(record));
        }
      });
    } catch (error, stack) {
      if (generation == _epoch && !_disposed) {
        try {
          await _invalidate('安全存储失败，请重新登录。');
        } catch (_) {}
      }
      try {
        await _queueRevocation(record);
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
    if (generation != _epoch || _disposed) {
      await _queueRevocation(record);
      throw const RemoteApiException(401, '登录操作已取消。');
    }
    _record = record;
    offline = false;
    error = null;
    _attach();
    api.installAccessToken(
      access,
      _now().add(Duration(seconds: seconds.toInt())),
    );
    _changed();
  }

  Future<void> login(String username, String password) async {
    await _authenticate('/mobile/auth/login', {
      'username': username.trim(),
      'password': password,
    });
  }

  Future<String> register({
    required String username,
    required String password,
    required String displayName,
    String consentVersion = 'account-sync-v1',
  }) async {
    final response = await _authenticate('/mobile/auth/register', {
      'username': username.trim(),
      'password': password,
      'display_name': displayName.trim(),
      'sync_consent_version': consentVersion,
    });
    final recovery = response['recovery_code'];
    if (recovery is! String || recovery.length < 20) {
      await logout();
      throw const FormatException('服务端未返回恢复码，请联系维护人员。');
    }
    return recovery;
  }

  Future<Map<String, dynamic>> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    if (busy) throw StateError('正在处理，请稍候。');
    if (_record != null) await logout();
    final generation = ++_epoch;
    busy = true;
    error = null;
    api.signOut();
    _changed();
    try {
      final result = await api.request('POST', path, data: body);
      await _accept(result, generation);
      unawaited(_drainRevocations());
      return result;
    } on RemoteApiException catch (e) {
      if (e.status == 404 || e.status == 501) {
        throw const RemoteApiException(503, '当前服务尚未启用账号注册和登录，请稍后重试。');
      }
      rethrow;
    } finally {
      if (generation == _epoch && !_disposed) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> refreshAccess() {
    final existing = _refreshing;
    if (existing != null) return existing;
    late final Future<void> pending;
    pending = _refresh().whenComplete(() {
      if (identical(_refreshing, pending)) _refreshing = null;
    });
    return _refreshing = pending;
  }

  Future<void> _refresh() async {
    final record = _record, generation = _epoch;
    if (record == null || !_expiry(record).isAfter(_now())) {
      await _invalidate('登录已过期，请联网后重新登录。');
      throw const RemoteApiException(401, '登录已过期，请重新登录。');
    }
    try {
      final body = await api.request(
        'POST',
        '/mobile/auth/refresh',
        data: {'refresh_token': record['refresh_token']},
      );
      await _accept(
        body,
        generation,
        expectedUser: record['user']['id'] as String,
        expectedPatient: record['patient']['id'] as String,
      );
    } on RemoteApiException catch (e) {
      if (generation == _epoch &&
          !_disposed &&
          (e.status == 401 || e.status == 403)) {
        await _invalidate('登录已失效，请重新登录。');
      }
      rethrow;
    } on FormatException {
      if (generation == _epoch && !_disposed) {
        await _invalidate('账号档案身份已变化，请重新登录核验。');
      }
      rethrow;
    }
  }

  Future<String> resetPassword(
    String username,
    String password,
    String recoveryCode,
  ) async {
    final result = await api.request(
      'POST',
      '/mobile/auth/reset-password',
      data: {
        'username': username.trim(),
        'password': password,
        'recovery_code': recoveryCode.trim(),
      },
    );
    final next = result['recovery_code'];
    if (next is! String || next.length < 20) {
      throw const FormatException('未收到新的恢复码，请联系维护人员。');
    }
    if (signedIn) await logout();
    return next;
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await api.request(
      'POST',
      '/mobile/auth/change-password',
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
    await logout();
  }

  Future<void> _invalidate(String message) async {
    ++_epoch;
    _refreshing = null;
    _record = null;
    offline = false;
    api.signOut();
    busy = false;
    error = message;
    _changed();
    await _serial(() => store.delete('session'));
  }

  Future<void> logout() async {
    final record = _record;
    try {
      await _invalidate('已退出登录。');
    } finally {
      if (record != null) {
        await _queueRevocation(record, waitForRemote: true);
      }
    }
  }

  Future<void> _queueRevocation(
    Map<String, dynamic> record, {
    bool waitForRemote = false,
  }) async {
    await _serial(() async {
      final old = await store.read('pending-revocations');
      final entries = old == null ? <dynamic>[] : jsonDecode(old) as List;
      entries.removeWhere(
        (value) =>
            !DateTime.parse(value['expires_at'] as String).isAfter(_now()),
      );
      final token = record['refresh_token'] as String;
      if (!entries.any((value) => value['refresh_token'] == token)) {
        entries.add({
          'base_url': record['base_url'],
          'refresh_token': token,
          'expires_at': record['refresh_expires_at'],
        });
      }
      await store.write('pending-revocations', jsonEncode(entries));
    });
    final revocation = _drainRevocations();
    if (waitForRemote) {
      // UI was already invalidated before disk/network work. An awaited logout
      // includes a bounded server ACK; offline failures remain encrypted.
      try {
        await revocation.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        /* Keep compensation for next authorized run. */
      }
    } else {
      unawaited(revocation);
    }
  }

  Future<void> _drainRevocations() async {
    try {
      final raw = await _serial(() => store.read('pending-revocations'));
      if (raw == null) return;
      for (final item in jsonDecode(raw) as List) {
        if (item['base_url'] != api.base.toString()) continue;
        await api.request(
          'POST',
          '/mobile/auth/logout',
          data: {'refresh_token': item['refresh_token']},
        );
        await _serial(() async {
          final current = await store.read('pending-revocations');
          final entries = current == null
              ? <dynamic>[]
              : jsonDecode(current) as List;
          entries.removeWhere(
            (entry) => entry['refresh_token'] == item['refresh_token'],
          );
          await store.write('pending-revocations', jsonEncode(entries));
        });
      }
    } catch (_) {
      // Encrypted compensation survives until next login/restore; never log it.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    api.signOut();
    super.dispose();
  }
}
