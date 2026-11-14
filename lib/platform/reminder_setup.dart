import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'plan_reminders.dart';

class ReminderSetupStatus {
  const ReminderSetupStatus({
    required this.notificationsAllowed,
    required this.exactAllowed,
    this.channelEnabled = true,
    this.family = 'standard',
    this.batteryUnrestricted = false,
    this.startupReviewRecommended = false,
    this.backgroundReviewRecommended = false,
  });

  final bool notificationsAllowed, exactAllowed, channelEnabled;
  final String family;
  final bool batteryUnrestricted;
  final bool startupReviewRecommended, backgroundReviewRecommended;
}

abstract interface class ReminderSetupGateway {
  Future<ReminderSetupStatus> read();
  Future<void> requestNotifications();
  Future<void> requestExact();
  Future<void> openNotifications();
  Future<void> openStartup();
  Future<void> openBackground();
}

class AndroidReminderSetupGateway implements ReminderSetupGateway {
  AndroidReminderSetupGateway({PlanReminders? reminders})
    : reminders = reminders ?? PlanReminders.instance;
  final PlanReminders reminders;
  static const channel = MethodChannel('piano_training/reminder_settings/v1');

  AndroidFlutterLocalNotificationsPlugin? get android => reminders.plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<ReminderSetupStatus> read() async {
    await reminders.initialize();
    final native = await channel.invokeMapMethod<String, dynamic>('getStatus');
    final channels = await android?.getNotificationChannels() ?? [];
    final enabled = !channels.any(
      (channel) =>
          channel.id == PlanReminders.channelId &&
          channel.importance == Importance.none,
    );
    return ReminderSetupStatus(
      notificationsAllowed: await android?.areNotificationsEnabled() == true,
      exactAllowed: await android?.canScheduleExactNotifications() == true,
      channelEnabled: enabled,
      family: native?['family'] as String? ?? 'other',
      batteryUnrestricted: native?['batteryUnrestricted'] == true,
      startupReviewRecommended: native?['startupReviewRecommended'] == true,
      backgroundReviewRecommended:
          native?['backgroundReviewRecommended'] == true,
    );
  }

  @override
  Future<void> requestNotifications() async {
    await reminders.request();
  }

  @override
  Future<void> requestExact() async {
    await android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> openNotifications() async {
    try {
      await _open('openNotificationDisplaySettings');
    } on MissingPluginException {
      if (await reminders.plugin.openAppNotificationSettings() != true) {
        throw StateError('Notification settings unavailable');
      }
    }
  }

  Future<void> _open(String method) async {
    final result = await channel.invokeMapMethod<String, dynamic>(method);
    if (result?['opened'] != true) {
      throw StateError('System settings unavailable');
    }
  }

  @override
  Future<void> openStartup() => _open('openAutoStartSettings');
  @override
  Future<void> openBackground() => _open('openBackgroundSettings');
}

enum ReminderSetupStep {
  checking,
  notifications,
  exact,
  startup,
  background,
  done,
}

/// Only standard notification/alarm permissions are requested automatically.
/// Vendor pages are opened by their own explicit controls.
class ReminderSetupController extends ChangeNotifier {
  ReminderSetupController(this.gateway);
  final ReminderSetupGateway gateway;
  ReminderSetupStatus? status;
  ReminderSetupStep step = ReminderSetupStep.checking;
  bool busy = false, failed = false;
  bool startupGuideReturned = false,
      backgroundGuideReturned = false,
      exactSkipped = false;
  bool startupOpened = false, backgroundOpened = false;
  bool _notificationAsked = false, _exactAsked = false, _disposed = false;
  bool _notificationSettingsOpened = false;
  ReminderSetupStep? _externalStep;
  bool _leftApp = false, _resumePending = false;

  bool get hasUnverifiedSettings =>
      startupGuideReturned ||
      backgroundGuideReturned && status?.batteryUnrestricted != true;

  ReminderSetupStep _next() {
    final s = status!;
    if (!s.notificationsAllowed || !s.channelEnabled) {
      return ReminderSetupStep.notifications;
    }
    if (!s.exactAllowed && !exactSkipped) return ReminderSetupStep.exact;
    return ReminderSetupStep.done;
  }

  Future<void> advance({bool skipExact = false, bool retry = false}) async {
    if (busy || _disposed) return;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      if (skipExact && step == ReminderSetupStep.exact) exactSkipped = true;
      while (!_disposed) {
        status = await gateway.read();
        if (_disposed) return;
        step = _next();
        if (step == ReminderSetupStep.notifications) {
          if (!_notificationAsked && !status!.notificationsAllowed) {
            _notificationAsked = true;
            await gateway.requestNotifications();
            continue;
          }
          if (retry ||
              status!.notificationsAllowed && !_notificationSettingsOpened) {
            _notificationSettingsOpened = true;
            await gateway.openNotifications();
          }
          break;
        }
        if (step == ReminderSetupStep.exact) {
          if (!_exactAsked || retry) {
            _exactAsked = true;
            retry = false;
            await gateway.requestExact();
            continue;
          }
          break;
        }
        break;
      }
    } catch (_) {
      if (!_disposed) failed = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
      if (_resumePending && !_disposed) {
        _resumePending = false;
        await advance();
      }
    }
  }

  Future<void> _openExternal(
    ReminderSetupStep target,
    Future<void> Function() open,
  ) async {
    _externalStep = target;
    _leftApp = false;
    try {
      await open();
    } catch (_) {
      _externalStep = null;
      _leftApp = false;
      rethrow;
    }
  }

  Future<void> openStartupGuide() =>
      _reviewExternal(ReminderSetupStep.startup, gateway.openStartup);
  Future<void> openBackgroundGuide() =>
      _reviewExternal(ReminderSetupStep.background, gateway.openBackground);

  Future<void> _reviewExternal(
    ReminderSetupStep target,
    Future<void> Function() open,
  ) async {
    if (busy || _disposed) return;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      await _openExternal(target, open);
      if (_disposed) return;
      if (target == ReminderSetupStep.startup) startupOpened = true;
      if (target == ReminderSetupStep.background) backgroundOpened = true;
    } catch (_) {
      if (!_disposed) failed = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
      if (_resumePending && !_disposed) {
        _resumePending = false;
        await advance();
      }
    }
  }

  void leftApp() {
    if (_externalStep != null) _leftApp = true;
  }

  Future<void> resumed() async {
    if (_disposed) return;
    // A queued resume from an earlier permission dialog must not consume a
    // settings page opened afterwards. Record the return at the event's time.
    if (_leftApp) {
      if (_externalStep == ReminderSetupStep.startup) {
        startupGuideReturned = true;
      }
      if (_externalStep == ReminderSetupStep.background) {
        backgroundGuideReturned = true;
      }
      _externalStep = null;
      _leftApp = false;
    }
    if (busy) {
      _resumePending = true;
      return;
    }
    await advance();
  }

  Future<void> reviewNotificationDisplay() async {
    if (busy || _disposed) return;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      await gateway.openNotifications();
    } catch (_) {
      if (!_disposed) failed = true;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
      if (_resumePending && !_disposed) {
        _resumePending = false;
        await advance();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
