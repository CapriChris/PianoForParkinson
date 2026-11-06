import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/practice_repository.dart';
import '../integration/auto_sync.dart';
import 'account_session.dart';

/// The global native lease serializes credential rotation across Flutter engines.
/// The per-account workspace lease is held until every DB consumer has closed.
class AccountBackground {
  static const _channel = MethodChannel('piano_training/account_sync/v1');
  static Future<bool> Function()? _foreground;

  static Future<bool> startForeground(
    Future<bool> Function() syncIfIdle, {
    int attempts = 30,
  }) async {
    _foreground = syncIfIdle;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'runForegroundSync') {
        throw MissingPluginException('Unsupported account sync operation');
      }
      try {
        return await _foreground?.call() ?? false;
      } catch (_) {
        return false;
      }
    });
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await _channel.invokeMethod<bool>('startForeground') == true) {
        return true;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    return false;
  }

  static Future<bool> acquireWorkspace(String accountDirectory) async {
    if (!RegExp(r'^account-[a-f0-9]{64}$').hasMatch(accountDirectory)) {
      throw const FormatException('Invalid account workspace');
    }
    return await _channel.invokeMethod<bool>('acquireWorkspace', {
          'account': accountDirectory,
        }) ==
        true;
  }

  static Future<void> releaseWorkspace() =>
      _channel.invokeMethod<void>('releaseWorkspace');
  static Future<void> schedule() => _channel.invokeMethod<void>('schedule');
  static Future<void> cancel() => _channel.invokeMethod<void>('cancel');
  static Future<String> storageRoot() async =>
      (await _channel.invokeMethod<String>('storageRoot'))!;

  static Future<bool> _headlessSync() async {
    final session = AccountSession();
    PracticeRepository? repository;
    AutoSync? sync;
    ValueNotifier<int>? updates;
    bool workspace = false;
    try {
      await session.restore();
      if (!session.signedIn) return true;
      if (session.offline) return false;
      final account = session.accountDirectory!;
      workspace = await acquireWorkspace(account);
      if (!workspace) return false;
      final directory = '${await storageRoot()}/$account';
      if (!await File('$directory/practice.db').exists()) return true;
      repository = PracticeRepository();
      await repository.openForBackground(directory);
      updates = ValueNotifier<int>(0);
      sync = AutoSync(repository, updates, () => true)..foreground = false;
      final device = repository.settings['device_local_id'] as String;
      final profile = repository.profile['profile_id'] as String;
      await sync.signIn(session.api, session.userId!, device, profile);
      final binding = await session.api.bindPatient(
        device,
        profile,
        session.patientId!,
      );
      await sync.setBinding(
        session.patientId!,
        binding['binding_id'] as String,
        ownedAccount: true,
      );
      final result = await sync.syncInBackground();
      return result.errors.isEmpty;
    } catch (_) {
      return false;
    } finally {
      await sync?.shutdown();
      updates?.dispose();
      if (repository != null && repository.db.isOpen) {
        await repository.db.close();
      }
      session.dispose();
      if (workspace) await releaseWorkspace();
    }
  }
}

/// Only WorkManager invokes this entry point. No AppController, camera service,
/// audio engine or model runtime is created by the headless Flutter engine.
@pragma('vm:entry-point')
Future<void> accountSyncBackgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final okay = await AccountBackground._headlessSync();
  await AccountBackground._channel.invokeMethod<void>('finished', {'ok': okay});
}
