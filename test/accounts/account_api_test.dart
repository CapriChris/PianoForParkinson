import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/accounts/account_session.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/integration/remote_api.dart';

class MemoryVault extends AccountVault {
  AccountSession? value;
  bool failWrite = false;
  String? revocations;
  @override
  Future<String?> readRevocations() async => revocations;
  @override
  Future<void> writeRevocations(String value) async {
    revocations = value;
  }

  @override
  Future<AccountSession?> read() async => value;
  @override
  Future<void> write(AccountSession session) async {
    if (failWrite) throw StateError('storage unavailable');
    value = session;
  }

  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<bool> acquire() async => true;
  @override
  Future<void> release() async {}
  @override
  Future<void> scheduleSync() async {}
  @override
  Future<void> cancelSync() async {}
}

Json response({
  String user = '11111111-1111-4111-8111-111111111111',
  String patient = '22222222-2222-4222-8222-222222222222',
}) => {
  'user': {
    'id': user,
    'username': 'patient_one',
    'display_name': '测试用户',
    'role': 'PATIENT',
  },
  'patient': {'id': patient, 'hospital_number': 'APP00000001', 'name': '测试用户'},
  'access_token': 'access-token',
  'refresh_token': 'r' * 64,
  'expires_in': 900,
  'refresh_expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(days: 30))
      .toIso8601String(),
};

AccountSession savedSession() => AccountSession.parse({
  ...response(),
  'device_id': 'device-one',
  'base': accountApiBase,
});

class AuthTransport extends RemoteApi {
  AuthTransport() : super(accountApiBase);
  final calls = <String>[];
  Json? registration;
  String? refreshPatient;
  Completer<void>? logoutGate;
  Completer<void>? gate;
  bool rejectRefresh = false, offline = false, forbidden = false;
  int refreshes = 0;
  @override
  Future<Json> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    calls.add(path);
    if (offline) throw const RemoteApiException(0, 'offline');
    if (path.endsWith('/register')) registration = data as Json;
    if (path.endsWith('/refresh')) {
      refreshes++;
      if (gate != null) await gate!.future;
      if (rejectRefresh) throw const RemoteApiException(401, 'expired');
      return {
        ...response(
          patient: refreshPatient ?? '22222222-2222-4222-8222-222222222222',
        ),
        'refresh_token': 'n' * 64,
      };
    }
    if (path.endsWith('/me') && forbidden) {
      throw const RemoteApiException(403, 'denied');
    }
    if (path.endsWith('/logout')) {
      await logoutGate?.future;
      return {};
    }
    return response();
  }
}

class DelayedVault extends MemoryVault {
  final writing = Completer<void>();
  final finishWrite = Completer<void>();
  @override
  Future<void> write(AccountSession session) async {
    if (!writing.isCompleted) writing.complete();
    await finishWrite.future;
    await super.write(session);
  }
}

void main() {
  test(
    'refresh persistence failure locks the old in-memory identity',
    () async {
      final vault = MemoryVault()
        ..value = savedSession()
        ..failWrite = true;
      var invalidated = false;
      final api = AccountApi(
        vault: vault,
        transport: AuthTransport(),
        invalidated: () => invalidated = true,
      )..session = vault.value;
      await expectLater(api.ensureAccess(), throwsStateError);
      expect(api.signedIn, isFalse);
      expect(vault.value, isNull);
      expect(invalidated, isTrue);
    },
  );
  test('refresh cannot substitute a different patient UUID', () async {
    final vault = MemoryVault()..value = savedSession();
    var invalidated = false;
    final api = AccountApi(
      vault: vault,
      transport: AuthTransport()
        ..refreshPatient = '33333333-3333-4333-8333-333333333333',
      invalidated: () => invalidated = true,
    )..session = vault.value;
    await expectLater(api.ensureAccess(), throwsFormatException);
    expect(api.signedIn, isFalse);
    expect(vault.value, isNull);
    expect(invalidated, isTrue);
  });
  test(
    'offline logout queues encrypted compensation and retry drains it',
    () async {
      final vault = MemoryVault()..value = savedSession();
      final transport = AuthTransport()..offline = true;
      final api = AccountApi(vault: vault, transport: transport)
        ..session = vault.value;
      await api.logout();
      expect(api.signedIn, isFalse);
      expect(vault.value, isNull);
      expect(
        (jsonDecode(vault.revocations!) as List).single['refresh_token'],
        savedSession().refreshToken,
      );
      transport.offline = false;
      await api.drainRevocations();
      expect(jsonDecode(vault.revocations!), isEmpty);
    },
  );
  test(
    'awaited logout includes the server revocation acknowledgment',
    () async {
      final vault = MemoryVault()..value = savedSession();
      final transport = AuthTransport()..logoutGate = Completer<void>();
      final api = AccountApi(vault: vault, transport: transport)
        ..session = vault.value;
      var done = false;
      final logout = api.logout().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(api.signedIn, isFalse);
      expect(done, isFalse);
      transport.logoutGate!.complete();
      await logout;
      expect(jsonDecode(vault.revocations!), isEmpty);
    },
  );
  test(
    'logout serializes credential deletion behind an in-progress write',
    () async {
      final vault = DelayedVault();
      final api = AccountApi(vault: vault, transport: AuthTransport());
      final login = api.authenticate('patient_one', 'a-password-123');
      final rejected = expectLater(login, throwsA(isA<RemoteApiException>()));
      await vault.writing.future;
      final logout = api.logout();
      vault.finishWrite.complete();
      await rejected;
      await logout;
      expect(vault.value, isNull);
      expect(api.signedIn, isFalse);
    },
  );
  test('registration accepts only server-owned patient identity and persists no access token', () async {
    final vault = MemoryVault(), transport = AuthTransport();
    final api = AccountApi(vault: vault, transport: transport);
    await api.authenticate(
      'Patient_One',
      'a-password-123',
      displayName: '测试用户',
    );
    expect(api.signedIn, isTrue);
    expect(transport.registration!['sync_consent_version'], 'account-sync-v1');
    expect(transport.registration!.containsKey('patient_id'), isFalse);
    expect(vault.value!.toJson().containsKey('access_token'), isFalse);
    expect(vault.value!.toJson().containsKey('password'), isFalse);
  });
  test(
    'restored session refreshes once across concurrent sync requests',
    () async {
      final vault = MemoryVault()..value = savedSession();
      final transport = AuthTransport()..gate = Completer<void>();
      final api = AccountApi(vault: vault, transport: transport)
        ..session = vault.value;
      final requests = [
        for (var i = 0; i < 4; i++) api.request('GET', '/mobile/auth/me'),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(transport.refreshes, 1);
      transport.gate!.complete();
      await Future.wait(requests);
      expect(vault.value!.refreshToken, 'n' * 64);
    },
  );
  test(
    'offline refresh preserves remembered login for local training',
    () async {
      final vault = MemoryVault()..value = savedSession();
      final api = AccountApi(
        vault: vault,
        transport: AuthTransport()..offline = true,
      )..session = vault.value;
      await expectLater(api.ensureAccess(), throwsA(isA<RemoteApiException>()));
      expect(api.signedIn, isTrue);
      expect(vault.value, isNotNull);
    },
  );
  test(
    'revoked refresh erases credential and invalidates protected UI',
    () async {
      final vault = MemoryVault()..value = savedSession();
      var invalidated = false;
      final api = AccountApi(
        vault: vault,
        transport: AuthTransport()..rejectRefresh = true,
        invalidated: () => invalidated = true,
      )..session = vault.value;
      await expectLater(api.ensureAccess(), throwsA(isA<RemoteApiException>()));
      expect(api.signedIn, isFalse);
      expect(vault.value, isNull);
      expect(invalidated, isTrue);
    },
  );
  test('logout cannot be undone by a late refresh reply', () async {
    final vault = MemoryVault()..value = savedSession();
    final transport = AuthTransport()..gate = Completer<void>();
    final api = AccountApi(vault: vault, transport: transport)
      ..session = vault.value;
    final refresh = api.ensureAccess();
    final rejected = expectLater(refresh, throwsA(isA<RemoteApiException>()));
    await Future<void>.delayed(Duration.zero);
    await api.logout();
    transport.gate!.complete();
    await rejected;
    expect(api.signedIn, isFalse);
    expect(vault.value, isNull);
    await api.drainRevocations();
    expect(transport.calls.where((path) => path.endsWith('/logout')).length, 2);
    expect(jsonDecode(vault.revocations!), isEmpty);
  });
  test('failed secure write never activates a login', () async {
    final vault = MemoryVault()..failWrite = true;
    final api = AccountApi(vault: vault, transport: AuthTransport());
    await expectLater(
      api.authenticate('patient_one', 'a-password-123'),
      throwsStateError,
    );
    expect(api.signedIn, isFalse);
  });
  test('account data directories stay stable and isolated', () {
    final a = savedSession();
    final b = AccountSession.parse({
      ...response(user: '33333333-3333-4333-8333-333333333333'),
      'device_id': 'other-device',
      'base': accountApiBase,
    });
    expect(a.directory, isNot(b.directory));
    expect(
      a.directory,
      AccountSession.parse({...a.toJson(), 'device_id': 'different-session'})
          .directory,
    );
    expect(
      () => AccountSession.parse({
        ...a.toJson(),
        'base': 'https://untrusted.example/api',
      }),
      throwsFormatException,
    );
  });
}
