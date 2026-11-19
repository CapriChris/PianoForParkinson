import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/domain/contracts.dart';
import 'package:piano_practice/integration/remote_api.dart';

import 'account_api_test.dart';

class ProfileTransport extends AuthTransport {
  String name = '医护新姓名';
  String? userId;
  bool conflict = false;
  Completer<void>? profileGate;
  Json? submitted;
  @override
  Future<Json> request(
    String method,
    String path, {
    Object? data,
    Map<String, String>? query,
  }) async {
    if (path == '/mobile/auth/me' || path == '/mobile/auth/profile') {
      if (offline) throw const RemoteApiException(0, 'offline');
      final snapshot = name;
      if (path.endsWith('/profile')) {
        submitted = data as Json;
        if (conflict) throw const RemoteApiException(409, '姓名已被修改');
        name = submitted!['display_name'] as String;
      }
      await profileGate?.future;
      final body = response(
        user: userId ?? '11111111-1111-4111-8111-111111111111',
      );
      return {
        'user': {
          ...body['user'] as Map,
          'display_name': method == 'PATCH' ? name : snapshot,
        },
        'patient': {
          ...body['patient'] as Map,
          'name': method == 'PATCH' ? name : snapshot,
        },
      };
    }
    final body = await super.request(method, path, data: data, query: query);
    if (userId != null && body['user'] is Map) {
      return {
        ...body,
        'user': {...body['user'] as Map, 'id': userId},
      };
    }
    return body;
  }
}

void main() {
  test('me persists canonical name without changing credentials or history partition', () async {
    final vault = MemoryVault();
    final api = AccountApi(vault: vault, transport: ProfileTransport());
    await api.authenticate('patient_one', 'password');
    final before = api.session!;
    final token = api.currentToken;
    await api.request('GET', '/mobile/auth/me');
    expect(api.session!.patient['name'], '医护新姓名');
    expect(vault.value!.patient['name'], '医护新姓名');
    expect(api.session!.directory, before.directory);
    expect(api.session!.deviceId, before.deviceId);
    expect(api.session!.refreshToken, before.refreshToken);
    expect(api.session!.refreshExpiresAt, before.refreshExpiresAt);
    expect(api.currentToken, token);
    expect(api.session!.user['username'], before.user['username']);
  });
  test(
    'profile sends expected name and persists only acknowledged name',
    () async {
      final transport = ProfileTransport();
      final vault = MemoryVault();
      final api = AccountApi(vault: vault, transport: transport);
      await api.authenticate('patient_one', 'password');
      await api.request(
        'PATCH',
        '/mobile/auth/profile',
        data: {'display_name': '新姓名', 'expected_name': '测试用户'},
      );
      expect(transport.submitted, {
        'display_name': '新姓名',
        'expected_name': '测试用户',
      });
      expect(api.session!.patient['name'], '新姓名');
      vault.failWrite = true;
      await expectLater(
        api.request(
          'PATCH',
          '/mobile/auth/profile',
          data: {'display_name': '未落盘', 'expected_name': '新姓名'},
        ),
        throwsStateError,
      );
      expect(api.session!.patient['name'], '新姓名');
    },
  );
  test('conflict and offline never optimistically change profile', () async {
    final transport = ProfileTransport()..conflict = true;
    final api = AccountApi(vault: MemoryVault(), transport: transport);
    await api.authenticate('patient_one', 'password');
    await expectLater(
      api.request(
        'PATCH',
        '/mobile/auth/profile',
        data: {'display_name': '覆盖', 'expected_name': '测试用户'},
      ),
      throwsA(isA<RemoteApiException>()),
    );
    expect(api.session!.patient['name'], '测试用户');
  });
  test('late me cannot roll back newer profile response', () async {
    final transport = ProfileTransport()..profileGate = Completer<void>();
    final api = AccountApi(vault: MemoryVault(), transport: transport);
    await api.authenticate('patient_one', 'password');
    final old = api.request('GET', '/mobile/auth/me');
    await Future<void>.delayed(Duration.zero);
    final gate = transport.profileGate!;
    transport.profileGate = null;
    await api.request(
      'PATCH',
      '/mobile/auth/profile',
      data: {'display_name': '最新', 'expected_name': '医护新姓名'},
    );
    gate.complete();
    await old;
    expect(api.session!.patient['name'], '最新');
  });
  test('late profile reply cannot restore logged out account', () async {
    final transport = ProfileTransport()..profileGate = Completer<void>();
    final vault = MemoryVault();
    final api = AccountApi(vault: vault, transport: transport);
    await api.authenticate('patient_one', 'password');
    final pending = api.request('GET', '/mobile/auth/me');
    await Future<void>.delayed(Duration.zero);
    api.signOut();
    transport.profileGate!.complete();
    await expectLater(pending, throwsA(isA<RemoteApiException>()));
    expect(api.session, isNull);
  });
  test(
    'successful save wins over me started while save is in flight',
    () async {
      final transport = ProfileTransport()..profileGate = Completer<void>();
      final api = AccountApi(vault: MemoryVault(), transport: transport);
      await api.authenticate('patient_one', 'password');
      final save = api.request(
        'PATCH',
        '/mobile/auth/profile',
        data: {'display_name': '最终姓名', 'expected_name': '测试用户'},
      );
      await Future<void>.delayed(Duration.zero);
      final gate = transport.profileGate!;
      transport.profileGate = null;
      transport.name = '旧快照';
      await api.request('GET', '/mobile/auth/me');
      transport.name = '最终姓名';
      gate.complete();
      await save;
      expect(api.session!.name, '最终姓名');
    },
  );
  test(
    'refresh started before save cannot restore old name or lose rotated token',
    () async {
      final transport = ProfileTransport()..gate = Completer<void>();
      final api = AccountApi(vault: MemoryVault(), transport: transport);
      await api.authenticate('patient_one', 'password');
      final refresh = api.ensureAccess(force: true);
      await Future<void>.delayed(Duration.zero);
      await api.updateName('保存后的姓名', '测试用户');
      transport.gate!.complete();
      await refresh;
      expect(api.session!.name, '保存后的姓名');
      expect(api.session!.refreshToken, 'n' * 64);
    },
  );

  test(
    'offline name save preserves secure session and creates no retry queue',
    () async {
      final transport = ProfileTransport();
      final vault = MemoryVault();
      final api = AccountApi(vault: vault, transport: transport);
      await api.authenticate('patient_one', 'password');
      final before = api.session!;
      transport.offline = true;
      await expectLater(
        api.updateName('离线姓名', before.name),
        throwsA(isA<RemoteApiException>()),
      );
      expect(identical(api.session, before), isTrue);
      expect(identical(vault.value, before), isTrue);
      expect(vault.revocations, isNull);
    },
  );
}
