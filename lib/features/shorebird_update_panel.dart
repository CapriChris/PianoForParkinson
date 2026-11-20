import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Explicit checks on the About page never block startup or restart training.
class ShorebirdUpdatePanel extends StatefulWidget {
  const ShorebirdUpdatePanel({super.key, required this.chinese, this.updater});
  final bool chinese;
  final ShorebirdUpdater? updater;

  @override
  State<ShorebirdUpdatePanel> createState() => _ShorebirdUpdatePanelState();
}

class _ShorebirdUpdatePanelState extends State<ShorebirdUpdatePanel> {
  late final ShorebirdUpdater _updater = widget.updater ?? ShorebirdUpdater();
  static const _track = UpdateTrack.stable;
  bool _busy = false;
  String? _status;
  String text(String zh, String en) => widget.chinese ? zh : en;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = text('正在检查热更新…', 'Checking for updates…');
    });
    try {
      if (!_updater.isAvailable) {
        if (mounted) {
          setState(
            () => _status = text(
              '此安装包不支持热更新，请使用网站批准的正式基础版本。',
              'This installation does not support patches. Use the approved base release.',
            ),
          );
        }
        return;
      }
      final status = await _updater.checkForUpdate(track: _track);
      if (!mounted) return;
      if (status == UpdateStatus.outdated) {
        setState(() => _status = text('正在下载更新…', 'Downloading update…'));
        await _updater.update(track: _track);
        final current = await _updater.readCurrentPatch();
        final next = await _updater.readNextPatch();
        if (!mounted) return;
        if (next == null || next.number == current?.number) {
          setState(
            () => _status = text(
              '当前没有等待生效的更新，可稍后重新检查。',
              'No update is waiting to apply. You can check again later.',
            ),
          );
          return;
        }
        setState(
          () => _status = text(
            '更新已准备好，下次完全退出并重新打开 App 后生效。请先完成当前训练。',
            'Update ready for the next cold start. Finish your training first.',
          ),
        );
      } else {
        setState(
          () => _status = status == UpdateStatus.restartRequired
              ? text('更新已准备好，重新启动后生效。', 'Update ready for the next cold start.')
              : status == UpdateStatus.unavailable
              ? text(
                  '暂时无法检查热更新，请稍后重试。',
                  'Update check unavailable. Please retry later.',
                )
              : text(
                  '当前没有待下载的更新，可继续使用当前版本。',
                  'No new patch was found at this check. You can keep using this version.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = text(
            '更新失败，仍可继续使用当前版本，请稍后重试。',
            'Update failed. You can continue using this version and retry later.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : _check,
        icon: const Icon(Icons.system_update_outlined),
        label: Text(text('检查热更新', 'Check for patches')),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Semantics(liveRegion: true, child: Text(_status!)),
        ),
    ],
  );
}
