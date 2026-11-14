import 'package:flutter/material.dart';

import '../app/page_title.dart';
import '../platform/reminder_setup.dart';
import '../ui/qin_components.dart';
import '../ui/qin_press.dart';

class ReminderSetupPage extends StatefulWidget {
  const ReminderSetupPage({super.key, required this.chinese, this.gateway});
  final bool chinese;
  final ReminderSetupGateway? gateway;
  @override
  State<ReminderSetupPage> createState() => _ReminderSetupPageState();
}

class _ReminderSetupPageState extends State<ReminderSetupPage>
    with WidgetsBindingObserver {
  late final flow = ReminderSetupController(
    widget.gateway ?? AndroidReminderSetupGateway(),
  );
  String t(String zh, String en) => widget.chinese ? zh : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    flow.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) flow.advance();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      flow.leftApp();
    }
    if (state == AppLifecycleState.resumed) flow.resumed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    flow.removeListener(changed);
    flow.dispose();
    super.dispose();
  }

  String get startupInstructions => switch (flow.status?.family) {
    'vivo' => t('找到“琴伴”，允许自启动。', 'Find Piano Companion and allow auto-start.'),
    'xiaomi' => t(
      '找到“琴伴”，开启“自启动”或“后台自启动”。',
      'Enable Auto-start or Background auto-start for Piano Companion.',
    ),
    'huawei' || 'honor' => t(
      '在“应用启动管理”中找到“琴伴”，允许自启动。',
      'Allow auto-launch for Piano Companion in App launch management.',
    ),
    'oppo' => t(
      '在“自启动管理”或“应用启动管理”中找到“琴伴”。',
      'Find Piano Companion in Auto launch or App launch management.',
    ),
    _ => t(
      '检查“琴伴”的自启动设置；没有此选项时无需设置。',
      'Check auto-start for Piano Companion. Skip if your phone has no such setting.',
    ),
  };
  String get backgroundInstructions => switch (flow.status?.family) {
    'vivo' => t(
      '电量 → 后台耗电管理 → 允许后台耗电。',
      'Battery → Background power consumption → Allow background power use.',
    ),
    'samsung' => t(
      '在后台使用限制中，将“琴伴”移出休眠或深度休眠应用。',
      'Keep Piano Companion out of Sleeping and Deep sleeping apps.',
    ),
    'xiaomi' => t(
      '在应用省电策略中，允许“琴伴”后台运行。',
      'Allow background activity in the app battery saver settings.',
    ),
    _ => t(
      '在应用电池设置中允许后台活动；没有此限制时无需更改。',
      'Allow background activity in app battery settings, if restricted.',
    ),
  };

  Widget item({
    required String title,
    required String subtitle,
    required bool verified,
    required Key buttonKey,
    VoidCallback? onEnable,
    bool unknown = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              verified
                  ? Icons.check_circle_outline
                  : unknown
                  ? Icons.help_outline
                  : Icons.radio_button_unchecked,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        if (onEnable != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: QinOutlinedButton(
              key: buttonKey,
              onPressed: flow.busy ? null : onEnable,
              child: Text(t('去开启', 'Open settings')),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = flow.status;
    final verifiedNotifications =
        s?.notificationsAllowed == true && s?.channelEnabled == true;
    return Scaffold(
      appBar: AppBar(
        leading: const QinBackButton(),
        title: PageTitle(t('提醒设置', 'Reminder setup')),
      ),
      body: QinActionPage(
        actions: [
          QinFilledButton(
            key: const ValueKey('reminder-setup-continue'),
            onPressed: flow.busy
                ? null
                : () {
                    if (flow.step == ReminderSetupStep.done && !flow.failed) {
                      Navigator.pop(context);
                    } else {
                      flow.advance(retry: true);
                    }
                  },
            child: Text(
              flow.failed
                  ? t('重试', 'Retry')
                  : flow.step == ReminderSetupStep.done
                  ? t('完成', 'Done')
                  : flow.step == ReminderSetupStep.exact
                  ? t('开启准时提醒', 'Allow exact alarms')
                  : t('继续', 'Continue'),
            ),
          ),
          if (flow.step == ReminderSetupStep.exact && !flow.busy)
            QinTextButton(
              key: const ValueKey('reminder-setup-skip-exact'),
              onPressed: () => flow.advance(skipExact: true),
              child: Text(t('使用普通提醒，继续', 'Use ordinary reminders')),
            ),
        ],
        children: [
          if (flow.busy) const LinearProgressIndicator(),
          if (flow.failed)
            QinStatus(
              tone: QinTone.warning,
              text: t(
                '暂时无法读取或打开系统设置，请重试。',
                'System settings could not be checked or opened. Please retry.',
              ),
            ),
          QinPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                item(
                  title: t('允许通知', 'Notifications'),
                  subtitle: verifiedNotifications
                      ? t('已检测开启', 'Enabled and verified')
                      : t(
                          '将自动申请通知权限',
                          'Notification permission is requested automatically',
                        ),
                  verified: verifiedNotifications,
                  buttonKey: const ValueKey('reminder-notifications-open'),
                  onEnable: verifiedNotifications
                      ? null
                      : () => flow.advance(retry: true),
                ),
                const Divider(),
                item(
                  title: t('准时提醒', 'Accurate reminders'),
                  subtitle: s?.exactAllowed == true
                      ? t('已检测开启', 'Enabled and verified')
                      : flow.exactSkipped
                      ? t(
                          '已选择普通提醒，可能延迟',
                          'Ordinary reminders selected; delivery may be delayed',
                        )
                      : t(
                          '将自动申请“闹钟和提醒”权限',
                          'Alarms and reminders access is requested automatically',
                        ),
                  verified: s?.exactAllowed == true,
                  buttonKey: const ValueKey('reminder-exact-open'),
                  onEnable: s?.exactAllowed == true
                      ? null
                      : () => flow.advance(retry: true),
                ),
                const Divider(),
                item(
                  title: t('通知显示', 'Notification display'),
                  subtitle: t(
                    '熄屏、锁屏和悬浮通知由手机系统控制，请在设置中开启。',
                    'Screen-off, lock-screen and pop-up display are controlled by your phone. Enable them in system settings.',
                  ),
                  verified: false,
                  unknown: true,
                  buttonKey: const ValueKey('reminder-display-settings'),
                  onEnable: flow.reviewNotificationDisplay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          QinPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s?.startupReviewRecommended == true) ...[
                  item(
                    title: t('自启动', 'Auto-start'),
                    subtitle: flow.startupGuideReturned
                        ? t('需核实：请以系统设置为准', 'Check manually in system settings')
                        : startupInstructions,
                    verified: false,
                    unknown: flow.startupGuideReturned,
                    buttonKey: const ValueKey('reminder-startup-open'),
                    onEnable: flow.openStartupGuide,
                  ),
                  const Divider(),
                ],
                item(
                  title: t('允许后台活动', 'Background activity'),
                  subtitle: s?.batteryUnrestricted == true
                      ? t(
                          '已检测：电池优化已放行',
                          'Battery optimization exemption detected',
                        )
                      : backgroundInstructions,
                  verified: s?.batteryUnrestricted == true,
                  unknown:
                      flow.backgroundGuideReturned &&
                      s?.batteryUnrestricted != true,
                  buttonKey: const ValueKey('reminder-background-open'),
                  onEnable: flow.openBackgroundGuide,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
