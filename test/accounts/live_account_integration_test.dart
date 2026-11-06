import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_session.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/integration/auto_sync.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'account_session_test.dart' show MemorySecureStore;

class _LocalCa extends HttpOverrides {
  _LocalCa(String cert)
    : context = (SecurityContext()..setTrustedCertificates(cert));
  final SecurityContext context;
  @override
  HttpClient createHttpClient(SecurityContext? _) =>
      super.createHttpClient(context);
}

void main() {
  final env = Platform.environment;
  final url = env['PD_SYNC_TEST_URL'];
  ffi.sqfliteFfiInit();
  sqlite.databaseFactory = ffi.databaseFactoryFfi;
  test(
    'actual mobile account API preserves own records across refresh and rejects foreign identities',
    skip: url == null ? 'Opt-in local HTTPS backend.' : false,
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      expect(Uri.parse(url!).host, '127.0.0.1');
      await HttpOverrides.runWithHttpOverrides(() async {
        final api = RemoteApi(url);
        expect((await api.request('GET', '/system/health'))['env'], 'test');
        final store = MemorySecureStore();
        final first = AccountSession(api: api, store: store);
        final user = 'qa_${DateTime.now().microsecondsSinceEpoch}';
        const password = 'local-test-only-password';
        final recovery = await first.register(
          username: user,
          password: password,
          displayName: 'Account QA',
        );
        expect(first.signedIn, isTrue);
        expect(first.hospitalNumber?.startsWith('P'), isTrue);
        final a = first.patientId!, aid = first.userId!;
        final workspace = first.accountDirectory!;
        expect(store.values['session']!.contains('access_token'), isFalse);
        final other = AccountSession(
          api: RemoteApi(url),
          store: MemorySecureStore(),
        );
        final otherCode = await other.register(
          username: '${user}_b',
          password: password,
          displayName: 'Other QA',
        );
        expect(otherCode.length >= 20, isTrue);
        expect(other.patientId == a, isFalse);
        expect(other.accountDirectory == workspace, isFalse);
        await expectLater(
          other.api.bindPatient('device-other', 'profile-other', a),
          throwsA(
            isA<RemoteApiException>().having((e) => e.status, 'status', 403),
          ),
        );
        await expectLater(
          api.request('GET', '/patients'),
          throwsA(
            isA<RemoteApiException>().having((e) => e.status, 'status', 403),
          ),
        );
        final root = await Directory.systemTemp.createTemp(
          'qin-accounts-live-',
        );
        final directory = Directory('${root.path}/$workspace');
        await directory.create();
        final db = await sqlite.openDatabase('${directory.path}/practice.db');
        for (final sql in [
          'CREATE TABLE sessions (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
          'CREATE TABLE piece_performances (session_id TEXT, profile_id TEXT, started_utc_ms INTEGER)',
        ]) {
          await db.execute(sql);
        }
        for (final sql in DatabaseSafety.migration4.split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
        final repo = PracticeRepository()
          ..db = db
          ..profile = {'profile_id': 'account-profile'};
        final updates = ValueNotifier(0);
        final sync = AutoSync(
          repo,
          updates,
          () => true,
          ownsRemoteSession: false,
        );
        try {
          await sync.signIn(
            api,
            aid,
            'stable-account-device',
            'account-profile',
          );
          final link = await api.bindPatient(
            'stable-account-device',
            'account-profile',
            a,
          );
          await sync.setBinding(
            a,
            link['binding_id'] as String,
            ownedAccount: true,
          );
          await sync.sync();
          final now = DateTime.now();
          final schedule = TrainingScheduleRepository(db, 'account-profile');
          await schedule.savePlan({
            'id': 'account-plan',
            'title': 'Two sessions',
            'kind': 'dance',
            'target_type': 'count',
            'target': 2,
            'start': localDay(now),
            'end': null,
            'days': [],
            'paused': false,
          });
          for (final id in ['first', 'second']) {
            await schedule.saveDance({
              'session_id': id,
              'started_utc_ms': now.millisecondsSinceEpoch,
              'active_ms': 30000,
              'covered_ms': 30000,
              'confirmed': true,
            });
            expect((await sync.sync()).errors, isEmpty);
            final progress = await api.request(
              'GET',
              '/integration/v1/plans',
              query: {'patient_id': a, 'on_date': localDay(now)},
            );
            expect(
              (progress['items'] as List).single['progress']['completed_units'],
              id == 'first' ? 1 : 2,
            );
          }
          expect((await sync.sync()).uploaded, 0);
          final plans = await api.request(
            'GET',
            '/integration/v1/plans',
            query: {'patient_id': a, 'on_date': localDay(now)},
          );
          expect(
            (plans['items'] as List).single['progress']['completed_units'],
            2,
          );
          await sync.shutdown();
          first.dispose();
          final resumed = AccountSession(api: RemoteApi(url), store: store);
          await resumed.restore();
          expect(resumed.userId, aid);
          expect(resumed.patientId, a);
          expect(resumed.accountDirectory, workspace);
          final again = await resumed.api.bindPatient(
            'stable-account-device',
            'account-profile',
            a,
          );
          expect(again['binding_id'], link['binding_id']);
          final token = resumed.api.currentToken!;
          await resumed.logout();
          final probe = RemoteApi(url)
            ..installAccessToken(
              token,
              DateTime.now().add(const Duration(minutes: 10)),
            );
          await expectLater(
            probe.request('GET', '/mobile/auth/me'),
            throwsA(
              isA<RemoteApiException>().having((e) => e.status, 'status', 401),
            ),
          );
          final nextCode = await resumed.resetPassword(
            user,
            'updated-local-test-password',
            recovery,
          );
          expect(nextCode == recovery, isFalse);
          await expectLater(
            resumed.resetPassword(user, 'other-local-test-password', recovery),
            throwsA(
              isA<RemoteApiException>().having((e) => e.status, 'status', 401),
            ),
          );
          await resumed.login(user, 'updated-local-test-password');
          await resumed.changePassword(
            'updated-local-test-password',
            'third-local-test-password',
          );
          expect(resumed.signedIn, isFalse);
          resumed.dispose();
          await other.logout();
          other.dispose();
        } finally {
          await sync.shutdown();
          updates.dispose();
          await db.close();
        }
      }, _LocalCa(env['PD_SYNC_TEST_CERT']!));
    },
  );
}
