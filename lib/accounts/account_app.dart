import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart';
import 'account_pages.dart';
import 'account_session.dart';
import 'background_sync.dart';

/// The production gate owns a whole Navigator and controller per account.
/// PianoApp(controller: ...) stays available unchanged for existing tests.
class AccountApplication extends StatefulWidget {
  const AccountApplication({super.key, this.session, this.usePlatform = true});
  final AccountSession? session;
  final bool usePlatform;
  @override
  State<AccountApplication> createState() => _AccountApplicationState();
}

class _AccountApplicationState extends State<AccountApplication> {
  late final session = widget.session ?? AccountSession();
  AppController? controller;
  String? mountedUser, error;
  bool restoring = true, recoveryPending = false, closed = false;
  int epoch = 0;
  Future<void> serial = Future.value();
  Timer? reconnect;
  Timer? expiryCheck;

  @override
  void initState() {
    super.initState();
    session.addListener(changed);
    expiryCheck = Timer.periodic(const Duration(minutes: 1), (_) => changed());
    unawaited(restore());
  }

  Future<bool> backgroundSync() async {
    final c = controller;
    if (c == null || !session.signedIn || !c.canSynchronizeAccount) {
      return false;
    }
    try {
      if (c.cloudSync.patient == null) return false;
      await c.cloudSync.syncInBackground();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> restore() async {
    try {
      if (widget.usePlatform &&
          !await AccountBackground.startForeground(backgroundSync)) {
        throw StateError('同步任务仍在关闭，请稍后重试。');
      }
      await session.restore();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      restoring = false;
      changed();
    }
  }

  void changed() {
    if (!mounted || closed) return;
    setState(() {});
    if (restoring || recoveryPending) return;
    final id = session.signedIn ? session.userId : null;
    if (id == mountedUser) return;
    mountedUser = id;
    final version = ++epoch;
    serial = serial
        .catchError((Object _) {})
        .then((_) => switchWorkspace(id, version));
  }

  Future<void> switchWorkspace(String? id, int version) async {
    final old = controller;
    controller = null;
    reconnect?.cancel();
    if (mounted) setState(() {});
    if (old != null) await old.shutdownAccount();
    if (widget.usePlatform) await AccountBackground.releaseWorkspace();
    if (id == null) {
      if (widget.usePlatform) await AccountBackground.cancel();
      return;
    }
    if (closed ||
        version != epoch ||
        !session.signedIn ||
        session.userId != id) {
      return;
    }
    try {
      final directory = session.accountDirectory!;
      if (widget.usePlatform &&
          !await AccountBackground.acquireWorkspace(directory)) {
        throw StateError('当前账号数据正在同步，请稍后重试。');
      }
      final c = AppController(
        databaseSubdirectory: directory,
        account: session,
      );
      controller = c;
      await c.initialize();
      if (closed ||
          version != epoch ||
          !session.signedIn ||
          session.userId != id) {
        return;
      }
      if (c.initialized) {
        unawaited(c.connectAccountAndSync().catchError((Object _) {}));
        reconnect = Timer.periodic(const Duration(seconds: 30), (_) {
          if (c.canSynchronizeAccount &&
              c.cloudSync.patient == null &&
              session.signedIn) {
            unawaited(c.connectAccountAndSync().catchError((Object _) {}));
          }
        });
        if (widget.usePlatform) await AccountBackground.schedule();
      }
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted && version == epoch) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    closed = true;
    epoch++;
    reconnect?.cancel();
    expiryCheck?.cancel();
    session.removeListener(changed);
    unawaited(
      serial.catchError((Object _) {}).then((_) async {
        await controller?.shutdownAccount();
        if (widget.usePlatform) await AccountBackground.releaseWorkspace();
        if (widget.session == null) session.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!restoring &&
        !recoveryPending &&
        session.signedIn &&
        c != null &&
        mountedUser == session.userId &&
        error == null) {
      return PianoApp(key: ValueKey(session.accountDirectory), controller: c);
    }
    return MaterialApp(
      key: ValueKey(
        session.signedIn && !recoveryPending
            ? 'account-loading'
            : 'account-auth',
      ),
      debugShowCheckedModeBanner: false,
      title: '琴伴',
      theme: accountTheme(),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh'), Locale('en')],
      locale: const Locale('zh'),
      home: restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : error != null
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: () {
                          setState(() => error = null);
                          mountedUser = null;
                          unawaited(restore());
                        },
                        child: const Text('重试'),
                      ),
                      TextButton(
                        onPressed: session.logout,
                        child: const Text('退出登录'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : !session.signedIn || recoveryPending
          ? AccountAuthPage(
              session: session,
              holdRecovery: (value) {
                recoveryPending = value;
                if (!value) changed();
              },
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
