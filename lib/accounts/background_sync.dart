import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/practice_repository.dart';
import '../integration/auto_sync.dart';
import '../integration/remote_api.dart';
import 'account_api.dart';
import 'account_session.dart';

const accountBackgroundChannel = MethodChannel(
  'piano_companion/background-sync/v1',
);

/// The native worker owns the account lease before opening this database.
/// It must never recover/finish an interrupted live training session.
Future<bool> syncRememberedAccount(
  String root, {
  AccountVault? vault,
  AccountApi? api,
  PracticeRepository? repository,
}) async {
  final credentials = vault ?? AccountVault();
  final saved = await credentials.read();
  if (saved == null) return true;
  if (saved.expired) {
    await credentials.clear();
    return true;
  }
  final path = '$root/${saved.directory}';
  if (!await File('$path/practice.db').exists()) return true;
  final store = repository ?? PracticeRepository();
  final updates = ValueNotifier<int>(0);
  AutoSync? sync;
  var opened = false;
  try {
    await store.open(path, 'zh-Hans', recoverInterrupted: false);
    opened = true;
    final remote = api ?? AccountApi(vault: credentials);
    remote.session = saved;
    await remote.drainRevocations();
    sync = AutoSync(store, updates, () => true);
    await sync.enrollAccount(
      remote,
      saved.userId,
      store.settings['device_local_id'] as String,
      store.profile['profile_id'] as String,
      saved.patientId,
    );
    final result = await sync.sync(automatic: true, background: true);
    return result.errors.isEmpty;
  } on RemoteApiException catch (e) {
    if (e.status == 401 || e.status == 403) {
      await credentials.clear();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    await sync?.close();
    updates.dispose();
    if (opened && store.db.isOpen) await store.db.close();
  }
}

Future<void> runAccountBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  var success = false;
  try {
    final root = await accountBackgroundChannel.invokeMethod<String>('storage');
    if (root != null) success = await syncRememberedAccount(root);
  } catch (_) {
    /* WorkManager retains the job for a later retry. */
  }
  await accountBackgroundChannel.invokeMethod<void>('finish', {
    'retry': !success,
  });
}
