import '../ui/qin_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart';
import '../integration/remote_api.dart';
import '../ui/qin_theme.dart';
import '../ui/qin_press.dart';
import 'account_controller.dart';
import 'password_rules.dart';
import 'external_account_pages.dart';
import '../platform/wechat_login.dart';

String accountError(Object error) {
  if (error is WechatLoginError) return error.message;
  if (error is RemoteApiException) {
    if (error.status == 404 || error.status == 405) {
      return '服务器尚未启用用户账号服务，请联系维护人员部署新版后端。';
    }
    if (error.status == 422) return '请检查填写内容后重试。';
    return error.message;
  }
  if (error is PlatformException) return '无法保存安全登录信息，请重试。';
  return '暂时无法完成操作，请检查网络后重试。';
}

class AccountApplication extends StatelessWidget {
  const AccountApplication({super.key, required this.accounts});
  final AccountController accounts;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: accounts,
    builder: (context, _) {
      if (accounts.app != null) {
        return PianoApp(
          key: ObjectKey(accounts.app),
          controller: accounts.app!,
        );
      }
      return MaterialApp(
        key: const ValueKey('account-login-app'),
        debugShowCheckedModeBanner: false,
        title: '琴伴',
        theme: qinTheme(highContrast: false),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: accounts.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : LoginPage(accounts: accounts),
      );
    },
  );
}

Future<void> showRecoveryCode(BuildContext context, String code) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: QinDialog(
          title: const Text('保存账号恢复码'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('忘记密码时可用此码重置密码。请保存在安全的地方，不要分享给他人。此码只显示一次。'),
                const SizedBox(height: 16),
                SelectableText(code),
              ],
            ),
          ),
          actions: [
            QinTextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('恢复码已复制')));
                }
              },
              child: const Text('复制恢复码'),
            ),
            QinFilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我已保存'),
            ),
          ],
        ),
      ),
    );

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.accounts});
  final AccountController accounts;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _AccountPasswordField extends StatefulWidget {
  const _AccountPasswordField({
    required this.id,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.validator,
    this.autofillHints,
    this.onSubmitted,
    this.helperText,
  });
  final String id, label;
  final TextEditingController controller;
  final bool enabled;
  final String? Function(String?) validator;
  final Iterable<String>? autofillHints;
  final void Function(String)? onSubmitted;
  final String? helperText;

  @override
  State<_AccountPasswordField> createState() => _AccountPasswordFieldState();
}

class _AccountPasswordFieldState extends State<_AccountPasswordField> {
  final focus = FocusNode();
  final toggleFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool visible = false;

  @override
  void initState() {
    super.initState();
    focus.addListener(focusChanged);
  }

  void focusChanged() {
    setState(() {
      if (!focus.hasFocus) visible = false;
    });
  }

  @override
  void dispose() {
    focus.removeListener(focusChanged);
    focus.dispose();
    toggleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(widget.id),
    controller: widget.controller,
    focusNode: focus,
    enabled: widget.enabled,
    obscureText: !visible,
    autocorrect: false,
    enableSuggestions: false,
    autofillHints: widget.autofillHints,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      helperMaxLines: 2,
      suffixIconConstraints: const BoxConstraints(
        minWidth: 48,
        maxWidth: 48,
        minHeight: 48,
      ),
      suffixIcon: focus.hasFocus
          ? QinPress(
              onActivate: widget.enabled
                  ? () => setState(() => visible = !visible)
                  : null,
              builder: (activate) => IconButton(
                key: ValueKey('${widget.id}-visibility'),
                focusNode: toggleFocus,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.zero,
                tooltip: visible ? '隐藏密码' : '显示密码',
                onPressed: activate,
                icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
              ),
            )
          : null,
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
  );
}

class AccountHeader extends StatelessWidget {
  const AccountHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 286,
        minWidth: double.infinity,
      ),
      child: Stack(
        key: const ValueKey('account-header'),
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/images/42-auth-shared-header.png',
                  key: const ValueKey('account-header-illustration'),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: 0),
                    background.withValues(alpha: .65),
                    background,
                  ],
                  stops: const [0, .62, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 144, 24, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '琴伴',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const Text('Piano Companion', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text(
                  title,
                  key: const ValueKey('account-page-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPageState extends State<LoginPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(), password = TextEditingController();
  final name = TextEditingController(),
      confirmation = TextEditingController(),
      recovery = TextEditingController();
  String mode = 'login';
  String? error;
  bool working = false;
  bool get register => mode == 'register';
  bool get reset => mode == 'reset';
  bool get busy => working || widget.accounts.busy;

  @override
  void dispose() {
    for (final field in [username, password, name, confirmation, recovery]) {
      field.dispose();
    }
    super.dispose();
  }

  void changeMode(String value) {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      mode = value;
      error = null;
      password.clear();
      confirmation.clear();
      recovery.clear();
    });
    form.currentState?.reset();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      working = true;
      error = null;
    });
    try {
      if (reset) {
        final code = await widget.accounts.api.resetPassword(
          username.text,
          password.text,
          recovery.text,
        );
        if (!mounted) return;
        await showRecoveryCode(context, code);
        if (!mounted) return;
        setState(() {
          mode = 'login';
          password.clear();
          confirmation.clear();
          recovery.clear();
          error = '密码已重置，请使用新密码登录。';
        });
      } else {
        final result = await widget.accounts.authenticate(
          username.text,
          password.text,
          displayName: register ? name.text : null,
        );
        if (!mounted) return;
        password.clear();
        confirmation.clear();
        if (result['recovery_code'] is String) {
          await showRecoveryCode(context, result['recovery_code'] as String);
        }
        if (!mounted) return;
        await widget.accounts.enter();
      }
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AccountHeader(
                title: reset
                    ? '重置密码'
                    : register
                    ? '创建账号'
                    : '登录账号',
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: AutofillGroup(
                      child: Form(
                        key: form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 18),
                            TextFormField(
                              key: const ValueKey('account-username'),
                              controller: username,
                              enabled: !busy,
                              decoration: InputDecoration(
                                labelText:
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'en'
                                    ? 'Login account'
                                    : '登录账号',
                                helperText: register ? '3–32 位字母、数字或下划线' : null,
                              ),
                              autofillHints: const [AutofillHints.username],
                              autocorrect: false,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? '请输入登录账号'
                                  : RegExp(r'^[A-Za-z0-9_]{3,32}$')
                                        .hasMatch(value.trim())
                                  ? null
                                  : '登录账号须为3-32位字母、数字或下划线',
                            ),
                            if (register) ...[
                              const SizedBox(height: 14),
                              ValueListenableBuilder<TextEditingValue>(
                                valueListenable: name,
                                builder: (context, value, _) => TextFormField(
                                  key: const ValueKey('account-nickname'),
                                  controller: name,
                                  enabled: !busy,
                                  maxLength: 64,
                                  buildCounter: (
                                    context, {
                                    required currentLength,
                                    required isFocused,
                                    maxLength,
                                  }) => null,
                                  decoration: InputDecoration(
                                    labelText: '姓名',
                                    suffixIcon: Align(
                                      alignment: Alignment.centerRight,
                                      widthFactor: 1,
                                      heightFactor: 1,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 12,
                                        ),
                                        child: Text(
                                          '${value.text.characters.length}/64',
                                          key: const ValueKey(
                                            'account-nickname-counter',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ),
                                  ),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? '请填写姓名'
                                      : null,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            _AccountPasswordField(
                              id: 'account-password',
                              controller: password,
                              enabled: !busy,
                              label: reset ? '新密码' : '密码',
                              autofillHints: [
                                register || reset
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              helperText: register || reset
                                  ? accountPasswordRequirement
                                  : null,
                              validator: (v) => register || reset
                                  ? validateNewAccountPassword(
                                      v,
                                      label: reset ? '新密码' : '密码',
                                    )
                                  : v == null || v.isEmpty
                                  ? '请输入密码'
                                  : null,
                              onSubmitted: (_) {
                                if (!register && !reset) submit();
                              },
                            ),
                            if (register || reset) ...[
                              const SizedBox(height: 14),
                              _AccountPasswordField(
                                id: 'account-confirmation',
                                controller: confirmation,
                                enabled: !busy,
                                label: '确认密码',
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                validator: (v) => v == null || v.isEmpty
                                    ? '请再次输入密码'
                                    : v == password.text
                                    ? null
                                    : '两次密码不一致',
                              ),
                            ],
                            if (reset) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: recovery,
                                enabled: !busy,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: '账号恢复码',
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? '请输入账号恢复码'
                                    : (v.trim().length) >= 20
                                    ? null
                                    : '请输入注册时保存的恢复码',
                              ),
                            ],
                            if (error ?? widget.accounts.message
                                case final String text)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  text,
                                  key: const ValueKey('account-error'),
                                ),
                              ),
                            const SizedBox(height: 18),
                            QinFilledButton(
                              key: const ValueKey('account-submit'),
                              onPressed: busy ? null : submit,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (busy) ...[
                                    const ExcludeSemantics(
                                      child: SizedBox(
                                        key: ValueKey(
                                          'account-submit-progress',
                                        ),
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Flexible(
                                    child: Semantics(
                                      liveRegion: busy,
                                      child: Text(
                                        busy
                                            ? reset
                                                  ? '重置中…'
                                                  : register
                                                  ? '注册中…'
                                                  : '登录中…'
                                            : reset
                                            ? '重置密码'
                                            : register
                                            ? '注册并登录'
                                            : '登录',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            QinTextButton(
                              onPressed: busy
                                  ? null
                                  : () => changeMode(
                                      register || reset ? 'login' : 'register',
                                    ),
                              child: Text(
                                register || reset ? '返回登录' : '没有账号？注册',
                              ),
                            ),
                            if (!register && !reset)
                              QinTextButton(
                                onPressed: busy
                                    ? null
                                    : () => changeMode('reset'),
                                child: const Text('忘记密码'),
                              ),
                            if (!register && !reset)
                              ExternalLoginActions(
                                accounts: widget.accounts,
                                onBusy: (value) {
                                  if (mounted) setState(() => working = value);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.c});
  final AppController c;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    widget.c.addListener(profileChanged);
    refreshName();
  }

  void profileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.c.removeListener(profileChanged);
    super.dispose();
  }

  Future<void> refreshName() async {
    try {
      await widget.c.accountApi!.refreshProfile();
    } catch (_) {
      if (mounted) {
        setState(
          () => message = widget.c.text(
            '暂时无法刷新姓名，请检查网络后重试。',
            'Unable to refresh your name. Check your connection and retry.',
          ),
        );
      }
    }
  }

  Future<void> editName() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.c.accountApi!.refreshProfile();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PatientNameDialog(c: widget.c),
      );
      if (saved == true && mounted) {
        setState(() => message = widget.c.text('姓名已保存', 'Name saved'));
      }
    } catch (e) {
      if (mounted) setState(() => message = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePassword() async {
    final old = TextEditingController(),
        next = TextEditingController(),
        again = TextEditingController();
    final form = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => QinDialog(
        title: const Text('修改密码'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: old,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码'),
                  validator: (v) => v?.isNotEmpty == true ? null : '请填写当前密码',
                ),
                TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    helperText: accountPasswordRequirement,
                  ),
                  validator: (v) => validateNewAccountPassword(v, label: '新密码'),
                ),
                TextFormField(
                  controller: again,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '确认新密码'),
                  validator: (v) => v == next.text ? null : '两次密码不一致',
                ),
              ],
            ),
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          QinFilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
    final oldValue = old.text, newValue = next.text;
    // Controllers are disposed after the dialog route finishes its transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    old.dispose();
    next.dispose();
    again.dispose();
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.c.accountApi!.changePassword(oldValue, newValue);
      await widget.c.onSignOut?.call();
    } catch (e) {
      if (mounted) setState(() => message = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, session = widget.c.accountApi!.session;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.text('我的账号', 'My account')),
        leading: ModalRoute.of(context)?.canPop == true
            ? QinIconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                icon: const BackButtonIcon(),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              c.text('姓名：', 'Name: ') + (session?.name ?? ''),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            QinOutlinedButton(
              key: const ValueKey('edit-patient-name'),
              onPressed: busy ? null : editName,
              child: Text(c.text('修改姓名', 'Edit name')),
            ),
            const SizedBox(height: 12),
            Text('档案编号：${session?.patient['hospital_number'] ?? ''}'),
            const SizedBox(height: 24),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_done_outlined),
              title: Text('自动同步已开启'),
              subtitle: Text('记录先保存在本机，网络可用时自动上传。'),
            ),
            ValueListenableBuilder<String>(
              valueListenable: c.cloudSync.message,
              builder: (_, value, _) => Text(value.isEmpty ? '正在准备同步…' : value),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!),
              ),
            const SizedBox(height: 16),
            AccountLoginMethods(
              c: c,
              disabled: busy,
              onBusy: (value) {
                if (mounted) setState(() => busy = value);
              },
            ),
            const SizedBox(height: 12),
            QinOutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        message = null;
                      });
                      try {
                        await c.connectAccount();
                        await c.cloudSync.sync();
                      } catch (e) {
                        if (mounted) setState(() => message = accountError(e));
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: const Text('立即同步'),
            ),
            const SizedBox(height: 12),
            QinOutlinedButton(
              onPressed: busy ? null : changePassword,
              child: const Text('修改密码'),
            ),
            const SizedBox(height: 24),
            QinTextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (context) => QinDialog(
                          title: const Text('退出账号？'),
                          content: const Text('本机记录会保留在此账号中。退出后需要登录才能使用训练和计划。'),
                          actions: [
                            QinTextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            QinFilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('退出登录'),
                            ),
                          ],
                        ),
                      );
                      if (yes == true) await c.onSignOut?.call();
                    },
              child: const Text('退出登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientNameDialog extends StatefulWidget {
  const _PatientNameDialog({required this.c});
  final AppController c;
  @override
  State<_PatientNameDialog> createState() => _PatientNameDialogState();
}

class _PatientNameDialogState extends State<_PatientNameDialog> {
  late final TextEditingController input;
  late String expectedName;
  late final String ownerUserId, ownerPatientId;

  @override
  void initState() {
    super.initState();
    final session = widget.c.accountApi!.session!;
    ownerUserId = session.userId;
    ownerPatientId = session.patientId;
    expectedName = session.name;
    input = TextEditingController(text: expectedName);
  }

  final form = GlobalKey<FormState>();
  bool saving = false, conflict = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    final c = widget.c;
    try {
      final session = c.accountApi!.session;
      if (session?.userId != ownerUserId ||
          session?.patientId != ownerPatientId) {
        throw const RemoteApiException(401, '登录状态已变化，请取消后重试。');
      }
      await c.accountApi!.updateName(input.text, expectedName);
      if (mounted) Navigator.pop(context, true);
    } on RemoteApiException catch (e) {
      if (e.status == 409) {
        try {
          await c.accountApi!.refreshProfile();
          if (!mounted) return;
          setState(() {
            expectedName = c.patientName;
            conflict = true;
            error = c.text(
              '医护端已将姓名改为“$expectedName”。请核对后再次确认保存，或取消。',
              'Your name is now “$expectedName”. Review it, then confirm saving your change or cancel.',
            );
          });
        } catch (_) {
          if (mounted) {
            setState(
              () => error = c.text(
                '姓名已在其他设备修改，暂时无法刷新。请取消后联网重试。',
                'Your name changed elsewhere. Unable to refresh; cancel and retry online.',
              ),
            );
          }
        }
      } else if (mounted) {
        setState(
          () => error = c.chinese
              ? accountError(e)
              : 'Unable to save your name. Check your connection and retry.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '姓名尚未确认保存，请联网重试。',
            'Your name has not been confirmed saved. Please retry online.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return PopScope(
      canPop: !saving,
      child: QinDialog(
        title: Text(c.text('修改姓名', 'Edit name')),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('patient-name-input'),
                  controller: input,
                  enabled: !saving,
                  maxLength: 64,
                  decoration: InputDecoration(labelText: c.text('姓名', 'Name')),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? c.text('请填写姓名', 'Enter your name')
                      : null,
                ),
                if (error != null)
                  Text(error!, key: const ValueKey('patient-name-error')),
              ],
            ),
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: Text(c.text('取消', 'Cancel')),
          ),
          QinFilledButton(
            key: const ValueKey('save-patient-name'),
            onPressed: saving ? null : save,
            child: Text(
              saving
                  ? c.text('正在保存…', 'Saving…')
                  : conflict
                  ? c.text('确认保存姓名', 'Confirm name change')
                  : c.text('保存', 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}
