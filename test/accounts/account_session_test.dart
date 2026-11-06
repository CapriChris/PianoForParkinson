import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_session.dart';
import 'package:piano_practice/accounts/secure_store.dart';
import 'package:piano_practice/integration/remote_api.dart';

class MemorySecureStore implements SecureAccountStore {
  final values = <String, String>{};
  bool failSessionWrite = false;
  Completer<void>? blockedWrite;
  final enteredWrite = Completer<void>();
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key == 'session') {
      if (failSessionWrite) throw StateError('test secure-store failure');
      if (blockedWrite != null) {
        if (!enteredWrite.isCompleted) enteredWrite.complete();
        await blockedWrite!.future;
      }
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class AccountApi extends RemoteApi {
  AccountApi(this.now) : super('https://test.example/api');
  final DateTime now;
  int refreshes = 0;
  String accountId = '11111111-1111-4111-8111-111111111111';
  String patientId = '22222222-2222-4222-8222-222222222222';
  int? failure;
  Completer<Map<String, dynamic>>? pendingRefresh;
  Completer<Map<String, dynamic>>? pendingLogout;
  Completer<void>? logoutStarted;
  final revoked = <String>[];
  Map<String, dynamic> response([
    String token = 'refresh-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ]) => {
    'access_token': 'access-token-never-persist',
    'refresh_token': token,
    'expires_in': 900,
    'refresh_expires_at': now.add(const Duration(days: 30)).toIso8601String(),
    'user': {
      'id': accountId,
      'username': 'test_user',
      'display_name': 'QA',
      'role': 'PATIENT',
    },
    'patient': {'id': patientId, 'name': 'QA', 'hospital_number': 'P000001'},
    'recovery_code': 'recovery-code-not-saved-aaaaaaaaaaaa',
  };
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    if (path == '/mobile/auth/logout') {
      if (failure == 0) throw const RemoteApiException(0, 'offline');
      logoutStarted?.complete();
      if (pendingLogout != null) await pendingLogout!.future;
      revoked.add((data as Map)['refresh_token'] as String);
      return {'message': 'done'};
    }
    if (failure != null) throw RemoteApiException(failure!, 'test failure');
    if (path == '/mobile/auth/refresh') {
      refreshes++;
      return pendingRefresh?.future ??
          response('rotated-refresh-bbbbbbbbbbbbbbbbbbbbbbbbbbb');
    }
    if (path == '/mobile/auth/reset-password') {
      return {'recovery_code': 'replacement-recovery-code-ccccccccccc'};
    }
    if (path == '/mobile/auth/change-password') return {'message': 'done'};
    return response();
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 6);
  test(
    'refresh cannot silently switch a saved account to a different patient',
    () async {
      final store = MemorySecureStore(), api = AccountApi(now);
      final account = AccountSession(api: api, store: store, now: () => now);
      await account.login('test_user', 'test-password');
      api.patientId = '55555555-5555-4555-8555-555555555555';
      await expectLater(account.refreshAccess(), throwsFormatException);
      expect(account.signedIn, isFalse);
      expect(store.values['session'], isNull);
      expect(api.currentToken, isNull);
      account.dispose();
    },
  );
  test('awaited logout includes online revocation ACK while UI is immediately signed out', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    api.pendingLogout = Completer();
    api.logoutStarted = Completer<void>();
    bool finished = false;
    final pending = account.logout().then((_) => finished = true);
    await api.logoutStarted!.future;
    expect(account.signedIn, isFalse);
    expect(api.currentToken, isNull);
    expect(finished, isFalse);
    api.pendingLogout!.complete({'message': 'done'});
    await pending;
    expect(api.revoked, contains('refresh-token-aaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
    expect(jsonDecode(store.values['pending-revocations']!), isEmpty);
    account.dispose();
  });
  test('offline logout clears local session and retains encrypted revocation compensation', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    api.failure = 0;
    await account.logout();
    expect(account.signedIn, isFalse);
    expect(api.currentToken, isNull);
    expect(store.values['session'], isNull);
    expect(jsonDecode(store.values['pending-revocations']!), hasLength(1));
    account.dispose();
  });
  test('register auto-authenticates, stores no password, access token or recovery code', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    final code = await account.register(
      username: 'test_user',
      password: 'test-password',
      displayName: 'QA',
    );
    expect(account.signedIn, isTrue);
    expect(account.patientId, api.patientId);
    expect(code, startsWith('recovery-code'));
    final stored = store.values['session']!;
    expect(stored, contains('refresh-token'));
    for (final secret in [
      'test-password',
      'access-token-never-persist',
      code,
    ]) {
      expect(stored, isNot(contains(secret)));
    }
    account.dispose();
  });

  test('concurrent refreshes share one request and save rotation before publishing', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    api.pendingRefresh = Completer();
    final a = account.refreshAccess(), b = account.refreshAccess();
    expect(identical(a, b), isTrue);
    expect(api.refreshes, 1);
    api.pendingRefresh!.complete(
      api.response('new-rotated-token-dddddddddddddddddddddddd'),
    );
    await Future.wait([a, b]);
    expect(store.values['session'], contains('new-rotated-token'));
    expect(account.signedIn, isTrue);
    account.dispose();
  });

  test('late refresh cannot reauthenticate after logout and its rotated token is revoked', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    api.pendingRefresh = Completer();
    final pending = account.refreshAccess();
    final expected = expectLater(pending, throwsA(isA<RemoteApiException>()));
    await account.logout();
    expect(account.signedIn, isFalse);
    api.pendingRefresh!.complete(
      api.response('late-rotation-eeeeeeeeeeeeeeeeeeeeeeeeeeee'),
    );
    await expected;
    await Future<void>.delayed(Duration.zero);
    expect(store.values['session'], isNull);
    expect(api.currentToken, isNull);
    expect(api.revoked, contains('late-rotation-eeeeeeeeeeeeeeeeeeeeeeeeeeee'));
    account.dispose();
  });

  test('logout serializes after an interrupted credential write and survives restore', () async {
    final store = MemorySecureStore()..blockedWrite = Completer<void>();
    final api = AccountApi(now),
        account = AccountSession(
          api: AccountApi(now),
          store: store,
          now: () => now,
        );
    final pending = account.login('test_user', 'test-password');
    final expected = expectLater(pending, throwsA(isA<RemoteApiException>()));
    await store.enteredWrite.future;
    final loggedOut = account.logout();
    expect(account.signedIn, isFalse);
    store.blockedWrite!.complete();
    await Future.wait([loggedOut, expected]);
    expect(store.values['session'], isNull);
    account.dispose();
    final restored = AccountSession(api: api, store: store, now: () => now);
    await restored.restore();
    expect(restored.signedIn, isFalse);
    restored.dispose();
  });

  test('failed secure credential persistence never publishes an authenticated session', () async {
    final store = MemorySecureStore()..failSessionWrite = true;
    final api = AccountApi(now),
        account = AccountSession(
          api: AccountApi(now),
          store: store,
          now: () => now,
        );
    await expectLater(
      account.login('test_user', 'test-password'),
      throwsStateError,
    );
    expect(account.signedIn, isFalse);
    expect(account.api.currentToken, isNull);
    expect(store.values['session'], isNull);
    expect(api.currentToken, isNull);
    account.dispose();
  });

  test('valid cached login can open offline, expired refresh cannot', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final first = AccountSession(api: api, store: store, now: () => now);
    await first.login('test_user', 'test-password');
    final path = first.accountDirectory;
    first.dispose();
    final offline = AccountSession(
      api: AccountApi(now)..failure = 0,
      store: store,
      now: () => now,
    );
    await offline.restore();
    expect(offline.signedIn, isTrue);
    expect(offline.offline, isTrue);
    expect(offline.accountDirectory, path);
    expect(offline.api.currentToken, isNull);
    offline.dispose();
    final expired = AccountSession(
      api: AccountApi(now),
      store: store,
      now: () => now.add(const Duration(days: 31)),
    );
    await expired.restore();
    expect(expired.signedIn, isFalse);
    expect(store.values['session'], isNull);
    expired.dispose();
  });

  test('account directories are stable and distinct; missing server cannot fake a login', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    final first = account.accountDirectory;
    expect(first, matches(RegExp(r'^account-[a-f0-9]{64}$')));
    await account.logout();
    api.accountId = '33333333-3333-4333-8333-333333333333';
    await account.login('other_user', 'test-password');
    expect(account.accountDirectory, isNot(first));
    await account.logout();
    api.failure = 404;
    await expectLater(
      account.login('test_user', 'test-password'),
      throwsA(
        isA<RemoteApiException>().having(
          (e) => e.message,
          'message',
          contains('尚未启用'),
        ),
      ),
    );
    expect(account.signedIn, isFalse);
    expect(store.values['session'], isNull);
    account.dispose();
  });

  test('revocation invalidates both memory and encrypted session', () async {
    final store = MemorySecureStore(), api = AccountApi(now);
    final account = AccountSession(api: api, store: store, now: () => now);
    await account.login('test_user', 'test-password');
    api.failure = 401;
    await expectLater(
      account.refreshAccess(),
      throwsA(isA<RemoteApiException>()),
    );
    expect(account.signedIn, isFalse);
    expect(account.api.signedIn, isFalse);
    expect(store.values['session'], isNull);
    account.dispose();
  });

  test(
    'foreign server credential envelope is not restored or transmitted',
    () async {
      final store = MemorySecureStore(), api = AccountApi(now);
      store.values['session'] = jsonEncode({
        ...api.response(),
        'base_url': 'https://other.example/api',
      });
      final account = AccountSession(api: api, store: store, now: () => now);
      await account.restore();
      expect(account.signedIn, isFalse);
      expect(api.refreshes, 0);
      account.dispose();
    },
  );
}
