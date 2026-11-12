import 'dart:async';

import 'package:flutter/widgets.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../platform/plan_reminders.dart';
import '../integration/remote_api.dart';
import 'account_api.dart';
import 'account_session.dart';
import 'background_sync.dart';

typedef AccountAppFactory = AppController Function(
  AccountApi api,
  AccountSession session,
  Future<void> Function() logout,
  void Function() invalidated,
);

class AccountController extends ChangeNotifier {
  AccountController({
    AccountVault? vault,
    AccountAppFactory? appFactory,
    RemoteApi? transport,
  }) : vault = vault ?? AccountVault(),
       appFactory = appFactory ?? _createApp {
    api = AccountApi(
      vault: this.vault,
      invalidated: () => unawaited(invalidate()),
      transport: transport,
    );
    accountBackgroundChannel.setMethodCallHandler((call) async {
      if (call.method != 'sync') return null;
      final current = app;
      if (current == null) return !busy;
      if (!current.initialized ||
          current.engine != null && !current.engine!.ended) {
        return false;
      }
      try {
        await current.connectAccount();
        final result = await current.cloudSync.sync(
          automatic: true,
          background: true,
        );
        return result.errors.isEmpty;
      } catch (_) {
        return false;
      }
    });
  }
  final AccountVault vault;
  final AccountAppFactory appFactory;
  late final AccountApi api;
  AppController? app;
  bool loading = true, busy = false;
  String? message;
  bool _closed = false;
  Future<void>? _leaving;
  Future<void>? _opening;
  bool _lease = false;
  void _schedule() {
    unawaited(vault.scheduleSync().catchError((Object _) {}));
  }

  Future<void> _acquire() async {
    if (_lease) return;
    for (var attempt = 0; attempt < 800; attempt++) {
      if (_closed) throw StateError('Account controller closed');
      if (await vault.acquire()) {
        _lease = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('后台同步尚未结束，请稍后重试。');
  }

  static AppController _createApp(
    AccountApi api,
    AccountSession session,
    Future<void> Function() logout,
    void Function() invalidated,
  ) => AppController(
    accountApi: api,
    databaseSubdirectory: session.directory,
    onSignOut: logout,
    onAccountInvalidated: invalidated,
  );

  void changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> restore() async {
    try {
      await _acquire();
      unawaited(api.drainRevocations());
      final saved = await vault.read();
      if (saved != null && !saved.expired) {
        api.session = saved;
        await _open(saved);
      } else if (saved != null) {
        await vault.clear();
        message = '登录已到期，请重新登录。';
      }
    } catch (_) {
      message = '无法恢复登录，请重新登录。';
    } finally {
      if (app == null && _lease) {
        await vault.release();
        _lease = false;
      }
      loading = false;
      changed();
    }
  }

  Future<void> _open(AccountSession session) async {
    if (_closed) return;
    final next = appFactory(
      api,
      session,
      logout,
      () => unawaited(invalidate()),
    );
    app = next;
    changed();
    _opening = next.initialize();
    await _opening;
    if (identical(app, next)) {
      next.trainingUpdates.addListener(_schedule);
      _schedule();
    }
  }

  Future<Json> authenticate(
    String username,
    String password, {
    String? displayName,
  }) async {
    if (busy || _leaving != null) throw StateError('请稍候。');
    busy = true;
    message = null;
    changed();
    try {
      await _acquire();
      final body = await api.authenticate(
        username,
        password,
        displayName: displayName,
      );
      // Registration recovery codes are acknowledged before opening the app.
      return body;
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> enter() async {
    if (api.session != null && app == null) await _open(api.session!);
  }

  Future<Json> authenticateSms(String challengeId, String code) =>
      _external(() => api.authenticateSms(challengeId, code));

  Future<Json> authenticateWechat(
    String challengeId,
    String code,
    String state,
  ) => _external(() => api.authenticateWechat(challengeId, code, state));

  Future<Json> _external(Future<Json> Function() authenticate) async {
    if (busy || _leaving != null || app != null) throw StateError('请稍候。');
    busy = true;
    message = null;
    changed();
    try {
      await _acquire();
      if (_closed) throw StateError('Account controller closed');
      return await authenticate();
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> invalidate() {
    message = '登录或档案权限已失效，请重新登录。';
    return logout();
  }

  Future<void> logout() =>
      _leaving ??= _logout().whenComplete(() => _leaving = null);
  Future<void> _logout() async {
    final old = app;
    busy = true;
    app = null;
    // Invalidate immediately, before UI disposal or network cleanup.
    Object? logoutError;
    final remoteLogout = api.logout().catchError((Object error) {
      logoutError = error;
    });
    changed();
    try {
      if (old != null) {
        old.trainingUpdates.removeListener(_schedule);
        old.pause('ACCOUNT_LOGOUT');
        await WidgetsBinding.instance.endOfFrame;
        await _opening;
        await old.shutdownAccount();
      }
      await PlanReminders.instance.clearForLogout();
      await remoteLogout;
      await vault.cancelSync();
      await vault.release();
      _lease = false;
      if (logoutError != null) throw logoutError!;
    } catch (_) {
      message = '已锁定训练；退出清理未完成，请重试退出。';
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    accountBackgroundChannel.setMethodCallHandler(null);
    app?.dispose();
    super.dispose();
  }
}
