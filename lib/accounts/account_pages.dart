import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../features/capture_widgets.dart';
import '../ui/qin_theme.dart';
import 'account_session.dart';

Future<void> showRecoveryCode(BuildContext context, String code) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('保存一次性恢复码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('忘记密码时需要此恢复码。请保存在安全位置；使用后会更换。'),
              const SizedBox(height: 16),
              SelectableText(code),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我已保存'),
          ),
        ],
      ),
    ),
  );
}

class AccountAuthPage extends StatefulWidget {
  const AccountAuthPage({
    super.key,
    required this.session,
    required this.holdRecovery,
  });
  final AccountSession session;
  final void Function(bool value) holdRecovery;
  @override
  State<AccountAuthPage> createState() => _AccountAuthPageState();
}

class _AccountAuthPageState extends State<AccountAuthPage> {
  final username = TextEditingController(), name = TextEditingController();
  final password = TextEditingController(),
      confirmation = TextEditingController(),
      code = TextEditingController();
  String mode = 'login', message = '';
  bool consent = false, sending = false, visible = false;
  Future<void> submit() async {
    if (sending) return;
    if (mode != 'login' && password.text != confirmation.text) {
      setState(() => message = '两次密码不一致。');
      return;
    }
    if (mode == 'register' && !consent) {
      setState(() => message = '请确认训练记录与计划的自动同步说明。');
      return;
    }
    setState(() {
      sending = true;
      message = '';
    });
    if (mode == 'register') widget.holdRecovery(true);
    try {
      if (mode == 'register') {
        final recovery = await widget.session.register(
          username: username.text.trim(),
          password: password.text,
          displayName: name.text.trim(),
        );
        password.clear();
        confirmation.clear();
        if (mounted) await showRecoveryCode(context, recovery);
      } else if (mode == 'reset') {
        final recovery = await widget.session.resetPassword(
          username.text.trim(),
          password.text,
          code.text.trim(),
        );
        password.clear();
        confirmation.clear();
        code.clear();
        if (mounted) {
          await showRecoveryCode(context, recovery);
          if (mounted) {
            setState(() {
              mode = 'login';
              message = '密码已重置，请重新登录。';
            });
          }
        }
      } else {
        await widget.session.login(username.text.trim(), password.text);
        password.clear();
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      widget.holdRecovery(false);
      if (mounted) setState(() => sending = false);
    }
  }

  void changeMode(String next) {
    if (sending) return;
    setState(() {
      mode = next;
      message = '';
      password.clear();
      confirmation.clear();
      code.clear();
      consent = false;
    });
  }

  @override
  void dispose() {
    for (final c in [username, name, password, confirmation, code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.music_note, size: 52),
              const SizedBox(height: 16),
              Text(
                '琴伴',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              Text(
                mode == 'register'
                    ? '注册账号'
                    : mode == 'reset'
                    ? '找回密码'
                    : '登录',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: username,
                enabled: !sending,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              if (mode == 'register') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  enabled: !sending,
                  decoration: const InputDecoration(labelText: '姓名或昵称'),
                ),
              ],
              if (mode == 'reset') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  enabled: !sending,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '一次性恢复码'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: password,
                enabled: !sending,
                obscureText: !visible,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: mode == 'reset' ? '新密码' : '密码',
                  suffixIcon: IconButton(
                    tooltip: visible ? '隐藏密码' : '显示密码',
                    onPressed: () => setState(() => visible = !visible),
                    icon: Icon(
                      visible ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              if (mode != 'login') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: confirmation,
                  enabled: !sending,
                  obscureText: !visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: '确认密码'),
                ),
              ],
              if (mode == 'register')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: consent,
                  onChanged: sending
                      ? null
                      : (v) => setState(() => consent = v == true),
                  title: const Text('我同意自动同步训练记录与计划'),
                  subtitle: const Text('录像采集与 AI 读取训练记录仍需分别授权。'),
                ),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: sending ? null : submit,
                child: Text(
                  sending
                      ? '请稍候…'
                      : mode == 'register'
                      ? '注册并登录'
                      : mode == 'reset'
                      ? '重置密码'
                      : '登录',
                ),
              ),
              if (mode == 'login') ...[
                TextButton(
                  onPressed: sending ? null : () => changeMode('register'),
                  child: const Text('注册账号'),
                ),
                TextButton(
                  onPressed: sending ? null : () => changeMode('reset'),
                  child: const Text('找回密码'),
                ),
              ] else
                TextButton(
                  onPressed: sending ? null : () => changeMode('login'),
                  child: const Text('返回登录'),
                ),
              if (mode == 'reset') const Text('如密码与恢复码均已遗失，请联系维护人员核验身份。'),
            ],
          ),
        ),
      ),
    ),
  );
}

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.c,
    required this.session,
  });
  final AppController c;
  final AccountSession session;
  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool busy = false;
  String message = '';
  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePassword() async {
    final old = TextEditingController(),
        next = TextEditingController(),
        again = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改密码'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: old,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码'),
                ),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '新密码'),
                ),
                TextField(
                  controller: again,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '确认新密码'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认修改'),
            ),
          ],
        ),
      );
      if (approved == true) {
        if (next.text != again.text) throw StateError('两次密码不一致。');
        await widget.session.changePassword(old.text, next.text);
      }
    } finally {
      old.dispose();
      next.dispose();
      again.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('我的账号与同步')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.session.displayName ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('用户名：${widget.session.username ?? ''}'),
          Text('患者编号：${widget.session.hospitalNumber ?? ''}'),
          Text(widget.session.offline ? '离线可用，联网后验证会话并补传' : '已登录'),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: widget.c.cloudSync.message,
            builder: (context, value, _) =>
                Text(value.isEmpty ? '等待同步' : value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() => widget.c.connectAccountAndSync()),
            child: const Text('立即同步'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CaptureLibraryPage(c: widget.c),
              ),
            ),
            child: const Text('面部采集与上传'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(changePassword),
            child: const Text('修改密码'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => run(widget.session.logout),
            child: const Text('退出登录'),
          ),
          if (message.isNotEmpty) Text(message),
          const SizedBox(height: 16),
          const Text('旧版未绑定记录已保留在本机，不会自动关联到当前账号。'),
        ],
      ),
    ),
  );
}

ThemeData accountTheme() => qinTheme(highContrast: false);
