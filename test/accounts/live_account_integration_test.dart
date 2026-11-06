import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_practice/accounts/account_api.dart';
import 'package:piano_practice/data/database_safety.dart';
import 'package:piano_practice/data/practice_repository.dart';
import 'package:piano_practice/data/training_schedule_repository.dart';
import 'package:piano_practice/domain/dance_training.dart';
import 'package:piano_practice/integration/auto_sync.dart';
import 'package:piano_practice/integration/remote_api.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

import 'account_api_test.dart' show MemoryVault;

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
        final store = MemoryVault();
        final first = AccountApi(vault: store);
        final user = 'qa_${DateTime.now().microsecondsSinceEpoch}';
        const password = 'local-test-only-password';
        final registered = await first.authenticate(
          user,
          password,
          displayName: 'Account QA',
        );
        final recovery = registered['recovery_code'] as String;
        expect(first.signedIn, isTrue);
        expect(
          (first.session!.patient['hospital_number'] as String).startsWith('P'),
          isTrue,
        );
        final a = first.session!.patientId, aid = first.session!.userId;
        final workspace = first.session!.directory;
        expect(store.value!.toJson().containsKey('access_token'), isFalse);
        final other = AccountApi(vault: MemoryVault());
        final otherBody = await other.authenticate(
          '${user}_b',
          password,
          displayName: 'Other QA',
        );
        expect((otherBody['recovery_code'] as String).length >= 20, isTrue);
        expect(other.session!.patientId == a, isFalse);
        expect(other.session!.directory == workspace, isFalse);
        await expectLater(
          other.bindPatient('device-other', 'profile-other', a),
          throwsA(
            isA<RemoteApiException>().having((e) => e.status, 'status', 403),
          ),
        );
        await expectLater(
          first.request('GET', '/patients'),
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
        final sync = AutoSync(repo, updates, () => true);
        try {
          await sync.enrollAccount(
            first,
            aid,
            'stable-account-device',
            'account-profile',
            a,
          );
          final link = await first.bindPatient(
            'stable-account-device',
            'account-profile',
            a,
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
            final progress = await first.request(
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
          final plans = await first.request(
            'GET',
            '/integration/v1/plans',
            query: {'patient_id': a, 'on_date': localDay(now)},
          );
          expect(
            (plans['items'] as List).single['progress']['completed_units'],
            2,
          );
          await sync.close();
          final resumed = AccountApi(vault: store)
            ..session = await store.read();
          await resumed.ensureAccess();
          expect(resumed.session!.userId, aid);
          expect(resumed.session!.patientId, a);
          expect(resumed.session!.directory, workspace);
          final again = await resumed.bindPatient(
            'stable-account-device',
            'account-profile',
            a,
          );
          expect(again['binding_id'], link['binding_id']);
          final token = resumed.currentToken!;
          await resumed.logout();
          final probe = RemoteApi(url)..setAccessToken(token);
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
          await resumed.authenticate(user, 'updated-local-test-password');
          await resumed.changePassword(
            'updated-local-test-password',
            'third-local-test-password',
          );
          await resumed.logout();
          expect(resumed.signedIn, isFalse);
          await other.logout();
        } finally {
          await sync.close();
          updates.dispose();
          await db.close();
        }
      }, _LocalCa(env['PD_SYNC_TEST_CERT']!));
    },
  );
}
