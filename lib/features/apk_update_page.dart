import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/apk_updates.dart';
import '../ui/qin_components.dart';
import '../ui/qin_dialog.dart';
import '../ui/qin_press.dart';

String _text(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// Checks on the idle entry screens, never from a training route.
class ApkUpdatePrompt extends StatefulWidget {
  const ApkUpdatePrompt({super.key, required this.child});
  final Widget child;

  @override
  State<ApkUpdatePrompt> createState() => _ApkUpdatePromptState();
}

class _ApkUpdatePromptState extends State<ApkUpdatePrompt> {
  @override
  void initState() {
    super.initState();
    if (ApkUpdates.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    final updates = ApkUpdates.instance;
    try {
      final update = await updates.check();
      if (update != null &&
          mounted &&
          ModalRoute.isCurrentOf(context) == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          MediaQuery.viewInsetsOf(context).bottom == 0 &&
          updates.markPrompted(update.versionCode)) {
        await _offer(context, update);
      }
    } catch (_) {
      // An unavailable manifest or network must never block opening the app.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ApkUpdateCheckButton extends StatefulWidget {
  const ApkUpdateCheckButton({super.key});

  @override
  State<ApkUpdateCheckButton> createState() => _ApkUpdateCheckButtonState();
}

class _ApkUpdateCheckButtonState extends State<ApkUpdateCheckButton> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final update = await ApkUpdates.instance.check();
      if (!mounted || ModalRoute.isCurrentOf(context) != true) return;
      if (update == null) {
        _message(_text(context, '暂未发现新版本。', 'No new version is available.'));
      } else {
        ApkUpdates.instance.markPrompted(update.versionCode);
        await _offer(context, update);
      }
    } catch (_) {
      if (mounted) {
        _message(
          _text(
            context,
            '暂时无法检查更新，请稍后重试。',
            'Could not check for updates. Try again later.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (!ApkUpdates.available) return const SizedBox.shrink();
    return QinOutlinedButton.icon(
      onPressed: _checking ? null : _check,
      icon: const Icon(Icons.system_update_alt),
      label: Text(
        _checking
            ? _text(context, '正在检查…', 'Checking…')
            : _text(context, '检查更新', 'Check for updates'),
      ),
    );
  }
}

Future<void> _offer(BuildContext context, ApkUpdate update) async {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  final notes = zh ? update.notesZh : update.notesEn;
  final size = (update.size / (1024 * 1024)).toStringAsFixed(1);
  final download = await showDialog<bool>(
    context: context,
    builder: (context) => QinDialog(
      title: Text(
        _text(
          context,
          '发现新版本 ${update.version}',
          'Version ${update.version} available',
        ),
      ),
      content: Text(
        [
          _text(context, '安装包大小 $size MiB', 'Download size: $size MiB'),
          if (notes.isNotEmpty) notes,
        ].join('\n\n'),
      ),
      actions: [
        QinOutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_text(context, '稍后', 'Later')),
        ),
        QinFilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(_text(context, '下载更新', 'Download update')),
        ),
      ],
    ),
  );
  if (download != true ||
      !context.mounted ||
      ModalRoute.isCurrentOf(context) != true) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => _ApkDownloadPage(update: update)),
  );
}

class _ApkDownloadPage extends StatefulWidget {
  const _ApkDownloadPage({required this.update});
  final ApkUpdate update;

  @override
  State<_ApkDownloadPage> createState() => _ApkDownloadPageState();
}

class _ApkDownloadPageState extends State<_ApkDownloadPage> {
  final _updates = ApkUpdates.instance;
  int? _progress;
  bool _downloading = false;
  bool _ready = false;
  bool _installing = false;
  bool _needsPermission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _download();
    });
  }

  @override
  void dispose() {
    if (_downloading) _updates.cancelDownload();
    super.dispose();
  }

  Future<void> _download() async {
    if (_downloading || _installing) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _ready = false;
      _needsPermission = false;
      _error = null;
    });
    try {
      await _updates.download(widget.update, (value) {
        final percent = (value * 100).floor();
        if (mounted && _progress != percent) {
          setState(() => _progress = percent);
        }
      });
      if (mounted) setState(() => _ready = true);
    } on ApkDownloadCancelled {
      if (mounted) setState(() => _progress = null);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error = _text(
            context,
            '安装包校验失败，请重新下载。',
            'The APK could not be verified. Download it again.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _text(
            context,
            '下载未完成。请检查网络或可用空间后重试。',
            'Download incomplete. Check your connection or free space and try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    if (_installing || !_ready) return;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      final opened = await _updates.install(widget.update);
      if (mounted) setState(() => _needsPermission = !opened);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'INVALID_APK') {
          _ready = false;
          _error = _text(
            context,
            '安装包不完整或与本机版本不匹配。请重试，或联系维护人员。',
            'The APK is incomplete or does not match your installed app. Try again or contact support.',
          );
        } else {
          _error = _text(
            context,
            '无法打开系统安装页面，请重试。',
            'Could not open the system installer. Try again.',
          );
        }
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _settings() async {
    try {
      await _updates.openInstallSettings();
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error = _text(
            context,
            '请在系统设置中允许琴伴安装应用。',
            'Allow Piano Companion to install apps in Android settings.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const QinBackButton(),
      title: Text(_text(context, '安装包更新', 'App update')),
    ),
    body: QinActionPage(
      actions: [
        if (_downloading)
          QinOutlinedButton(
            onPressed: _updates.cancelDownload,
            child: Text(_text(context, '取消下载', 'Cancel download')),
          )
        else if (_ready) ...[
          if (_needsPermission)
            QinOutlinedButton(
              onPressed: _settings,
              child: Text(_text(context, '打开安装权限', 'Open install permission')),
            ),
          QinFilledButton(
            onPressed: _installing ? null : _install,
            child: Text(_text(context, '安装更新', 'Install update')),
          ),
        ] else
          QinFilledButton(
            onPressed: _download,
            child: Text(_text(context, '重新下载', 'Download again')),
          ),
      ],
      children: [
        Text(
          widget.update.version,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (_downloading) ...[
          LinearProgressIndicator(value: (_progress ?? 0) / 100),
          const SizedBox(height: 8),
          Text(
            _progress == 100
                ? _text(context, '正在校验安装包…', 'Verifying the APK…')
                : _text(context, '正在下载 $_progress%', 'Downloading $_progress%'),
          ),
        ],
        if (_ready)
          Text(
            _text(
              context,
              '安装包已下载。请在 Android 安装界面确认更新，完成后打开琴伴。',
              'The APK is ready. Confirm the update in Android, then open Piano Companion.',
            ),
          ),
        if (_needsPermission) ...[
          const SizedBox(height: 12),
          Text(
            _text(
              context,
              '请允许琴伴安装应用，返回后再点「安装更新」。',
              'Allow Piano Companion to install apps, then return and tap Install update.',
            ),
          ),
        ],
        if (_error case final error?) QinStatus(text: error),
        if (!_downloading && !_ready && _error == null)
          Text(_text(context, '下载已取消。', 'Download cancelled.')),
      ],
    ),
  );
}
