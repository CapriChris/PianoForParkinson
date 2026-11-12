import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../integration/remote_api.dart';
import '../ui/qin_press.dart';
import 'account_api.dart';
import 'account_controller.dart';
import 'account_pages.dart';

Widget _progressLabel(bool busy, String idle, String waiting) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    if (busy) ...[
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 10),
    ],
    Flexible(child: Text(busy ? waiting : idle)),
  ],
);

class ExternalLoginActions extends StatefulWidget {
  const ExternalLoginActions({
    super.key,
    required this.accounts,
    required this.onBusy,
  });
  final AccountController accounts;
  final ValueChanged<bool> onBusy;
  @override
  State<ExternalLoginActions> createState() => _ExternalLoginActionsState();
}

class _ExternalLoginActionsState extends State<ExternalLoginActions> {
  bool working = false;
  String? message;

  Future<void> openPhone() async {
    if (working || widget.accounts.busy) return;
    setState(() {
      working = true;
      message = null;
    });
    widget.onBusy(true);
    try {
      Json providers;
      try {
        providers = await widget.accounts.api.loginProviders();
      } catch (_) {
        providers = {};
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PhoneAccountPage(
            api: widget.accounts.api,
            accounts: widget.accounts,
            available: providers['sms_enabled'] == true,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => message = accountError(error));
    } finally {
      if (mounted) {
        setState(() => working = false);
        widget.onBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 12),
      QinTextButton.icon(
        key: const ValueKey('phone-login'),
        onPressed: working || widget.accounts.busy ? null : openPhone,
        icon: const Icon(Icons.phone_android),
        label: const Text('手机号登录'),
      ),
      if (working) const LinearProgressIndicator(),
      const Text('已有账号请先登录，再到“我的账号”绑定手机号。', textAlign: TextAlign.center),
      if (message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(message!, textAlign: TextAlign.center),
        ),
    ],
  );
}

class PhoneAccountPage extends StatefulWidget {
  const PhoneAccountPage({
    super.key,
    required this.api,
    this.accounts,
    this.binding = false,
    required this.available,
    this.now,
  });
  final AccountApi api;
  final AccountController? accounts;
  final bool binding, available;
  final DateTime Function()? now;
  @override
  State<PhoneAccountPage> createState() => _PhoneAccountPageState();
}

class _PhoneAccountPageState extends State<PhoneAccountPage> {
  final phone = TextEditingController(), code = TextEditingController();
  final form = GlobalKey<FormState>();
  Timer? timer;
  DateTime? retryAt, expiresAt;
  String? challengeId, sentPhone, message;
  String? operation;
  bool get busy => operation != null;
  DateTime get now => widget.now?.call() ?? DateTime.now();
  int get remaining => retryAt == null
      ? 0
      : math.max(0, (retryAt!.difference(now).inMilliseconds / 1000).ceil());
  String get normalizedPhone =>
      phone.text.trim().replaceFirst(RegExp(r'^\+86'), '');

  Future<void> send() async {
    if (busy || !widget.available || remaining > 0) return;
    if (!RegExp(r'^1[3-9][0-9]{9}$').hasMatch(normalizedPhone)) {
      setState(
        () => message = phone.text.trim().isEmpty ? '请输入手机号' : '请输入有效的中国大陆手机号',
      );
      return;
    }
    setState(() {
      operation = 'send';
      message = null;
      challengeId = sentPhone = null;
      code.clear();
    });
    try {
      final number = normalizedPhone;
      final result = await widget.api.sendSms(number, binding: widget.binding);
      if (!mounted) return;
      setState(() {
        challengeId = result['challenge_id'] as String;
        sentPhone = number;
        code.clear();
        retryAt = now.add(
          Duration(
            seconds: (result['retry_after'] as int? ?? 60).clamp(1, 3600),
          ),
        );
        expiresAt = now.add(
          Duration(seconds: result['expires_in'] as int? ?? 300),
        );
        message = '验证码已发送，请查看短信。';
      });
      startTimer();
    } catch (error) {
      if (mounted) {
        setState(() {
          message = accountError(error);
          if (error is RemoteApiException && error.retryAfter != null) {
            retryAt = now.add(error.retryAfter!);
          }
        });
        if (remaining > 0) startTimer();
      }
    } finally {
      if (mounted) setState(() => operation = null);
    }
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (value) {
      if (!mounted || remaining == 0) value.cancel();
      if (mounted) setState(() {});
    });
  }

  Future<void> submit() async {
    if (busy || !widget.available || !form.currentState!.validate()) return;
    if (challengeId == null ||
        sentPhone != normalizedPhone ||
        expiresAt?.isAfter(now) != true) {
      setState(() => message = '请先获取当前手机号的有效验证码。');
      return;
    }
    setState(() {
      operation = 'login';
      message = null;
    });
    FocusScope.of(context).unfocus();
    try {
      if (widget.binding) {
        await widget.api.bindSms(challengeId!, code.text);
        if (mounted) Navigator.pop(context, true);
      } else {
        final result = await widget.accounts!.authenticateSms(
          challengeId!,
          code.text,
        );
        if (!mounted) return;
        if (result['recovery_code'] is String) {
          await showRecoveryCode(context, result['recovery_code'] as String);
        }
        if (mounted) await widget.accounts!.enter();
      }
    } catch (error) {
      if (mounted) setState(() => message = accountError(error));
    } finally {
      if (mounted) setState(() => operation = null);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      body: SafeArea(
        child: Stack(
          key: const ValueKey('phone-page-stack'),
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  AccountHeader(title: widget.binding ? '绑定手机号' : '手机号登录'),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 508),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!widget.available)
                                const Text('手机号登录暂未开通，请使用账号密码登录。'),
                              if (widget.available && !widget.binding)
                                const Text('未绑定的手机号将创建新账号；已有账号请先登录后绑定。'),
                              TextFormField(
                                key: const ValueKey('sms-phone'),
                                controller: phone,
                                enabled: !busy && widget.available,
                                keyboardType: TextInputType.phone,
                                autofillHints: const [
                                  AutofillHints.telephoneNumberNational,
                                ],
                                decoration: const InputDecoration(
                                  labelText: '手机号',
                                  prefixText: '+86 ',
                                ),
                                validator: (_) => normalizedPhone.isEmpty
                                    ? '请输入手机号'
                                    : RegExp(r'^1[3-9][0-9]{9}$')
                                          .hasMatch(normalizedPhone)
                                    ? null
                                    : '请输入有效的中国大陆手机号',
                                onChanged: (_) {
                                  if (sentPhone != normalizedPhone) {
                                    setState(() {
                                      challengeId = null;
                                      code.clear();
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      key: const ValueKey('sms-code'),
                                      controller: code,
                                      enabled: !busy && widget.available,
                                      keyboardType: TextInputType.number,
                                      autofillHints: const [
                                        AutofillHints.oneTimeCode,
                                      ],
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(6),
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: '短信验证码',
                                      ),
                                      validator: (value) =>
                                          value?.isEmpty != false
                                          ? '请输入验证码'
                                          : RegExp(r'^[0-9]{6}$')
                                                .hasMatch(value!)
                                          ? null
                                          : '请输入6位验证码',
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: QinTextButton(
                                      key: const ValueKey('sms-send'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        minimumSize: const Size(0, 60),
                                      ),
                                      onPressed:
                                          busy ||
                                              !widget.available ||
                                              remaining > 0
                                          ? null
                                          : send,
                                      child: _progressLabel(
                                        operation == 'send',
                                        remaining > 0
                                            ? '$remaining秒后重发'
                                            : '获取验证码',
                                        '发送中…',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (message != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(message!),
                                ),
                              const SizedBox(height: 12),
                              QinFilledButton(
                                key: const ValueKey('sms-submit'),
                                onPressed: busy || !widget.available
                                    ? null
                                    : submit,
                                child: _progressLabel(
                                  operation == 'login',
                                  widget.binding ? '确认绑定' : '登录',
                                  widget.binding ? '绑定中…' : '登录中…',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              width: kToolbarHeight,
              height: kToolbarHeight,
              child: QinIconButton(
                key: const ValueKey('phone-back-button'),
                onPressed: busy ? null : () => Navigator.maybePop(context),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const BackButtonIcon(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AccountLoginMethods extends StatefulWidget {
  const AccountLoginMethods({
    super.key,
    required this.c,
    required this.onBusy,
    required this.disabled,
  });
  final AppController c;
  final ValueChanged<bool> onBusy;
  final bool disabled;
  @override
  State<AccountLoginMethods> createState() => _AccountLoginMethodsState();
}

class _AccountLoginMethodsState extends State<AccountLoginMethods> {
  bool working = false, loaded = false;
  Json providers = {};
  List<Json> identities = [];
  String? message;
  AccountApi get api => widget.c.accountApi!;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        api.loginProviders(),
        api.loginIdentities(),
      ]);
      if (!mounted) return;
      setState(() {
        providers = results[0];
        identities = (results[1]['items'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<void> bindPhone() async {
    if (working || !loaded || widget.disabled) return;
    setState(() {
      working = true;
      message = null;
    });
    widget.onBusy(true);
    try {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PhoneAccountPage(
            api: api,
            binding: true,
            available: providers['sms_enabled'] == true,
          ),
        ),
      );
      if (result != true) return;
      await load();
      if (mounted) setState(() => message = '绑定成功，训练记录和患者编号保持不变。');
    } catch (error) {
      if (mounted) setState(() => message = accountError(error));
    } finally {
      if (mounted) {
        setState(() => working = false);
        widget.onBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = identities.where((e) => e['provider'] == 'sms').firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('登录方式', style: Theme.of(context).textTheme.titleMedium),
        if (phone != null) Text('手机号：${phone['label']}'),
        QinOutlinedButton(
          onPressed: working || widget.disabled || !loaded || phone != null
              ? null
              : bindPhone,
          child: Text(phone != null ? '手机号已绑定' : '绑定手机号'),
        ),
        if (working) const LinearProgressIndicator(),
        if (message != null) Text(message!),
      ],
    );
  }
}
