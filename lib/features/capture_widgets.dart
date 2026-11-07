import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../integration/remote_pages.dart';
import '../integration/training_capture.dart';
import '../ui/qin_components.dart';
import '../ui/qin_press.dart';

class CapturePreparation extends StatefulWidget {
  const CapturePreparation({super.key, required this.c});
  final AppController c;
  @override
  State<CapturePreparation> createState() => CapturePreparationState();
}

class CapturePreparationState extends State<CapturePreparation> {
  TrainingCapture? capture;
  bool busy = false;
  String? error;
  void captureChanged() {
    if (mounted) setState(() {});
  }

  TrainingCapture? claim() {
    if (capture?.finished == true || capture?.state == 'STOPPED') return null;
    capture?.claimed = true;
    return capture;
  }

  Future<void> toggle(bool value) async {
    if (busy) return;
    if (!value) {
      await capture?.discard();
      capture?.removeListener(captureChanged);
      if (mounted) setState(() => capture = null);
      return;
    }
    final c = widget.c;
    if (capture?.state == 'STOPPED' && capture?.claimed == false) {
      await capture!.discard();
      capture!.removeListener(captureChanged);
      capture = null;
    }
    if (!mounted) return;
    if (!c.captures.connected) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CloudIntegrationPage(controller: c),
        ),
      );
      if (!mounted || !c.captures.connected) return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.text('开启本次面部采集？', 'Record this practice?')),
        content: Text(
          c.text(
            '使用前置摄像头记录本次训练，不录音。保存练习后，视频将发送至已绑定档案的 Web 服务用于面部分析，并由有权限的人员复核。默认等待 Wi-Fi 上传。待上传视频在本机最多保留 7 天，你可以随时停止采集或删除视频。',
            'Record this practice with the front camera, without audio. After saving, upload to the linked Web service for face analysis and authorized review. Upload waits for Wi-Fi by default. Pending videos stay on this device for up to 7 days. You can stop recording or delete videos at any time.',
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('取消', 'Cancel')),
          ),
          QinFilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.text('同意并开启', 'Agree and enable')),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await c.captures.prepare();
      if (!mounted) {
        await next.discard();
        return;
      }
      next.addListener(captureChanged);
      setState(() => capture = next);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '无法开启采集，请检查相机权限、存储空间及 Web 服务配置。训练仍可继续。',
            'Unable to record. Check camera permission, storage and the Web service. You can still practice.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    capture?.removeListener(captureChanged);
    if (capture?.claimed == false) unawaited(capture!.discard());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: QinPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.videocam_outlined),
              title: Text(c.text('面部视频采集', 'Face recording')),
              subtitle: Text(
                c.text('训练后上传分析，可选', 'Optional analysis after practice'),
              ),
              value:
                  capture != null &&
                  !capture!.finished &&
                  capture!.state != 'STOPPED',
              onChanged: busy ? null : toggle,
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (capture?.camera?.value.isInitialized == true &&
                !capture!.finished) ...[
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, box) => Center(
                  child: SizedBox(
                    width: box.maxWidth * .55,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CameraPreview(capture!.camera!),
                    ),
                  ),
                ),
              ),
              Text(
                c.text('请让面部保持在画面内', 'Keep your face in view'),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CaptureIndicator extends StatelessWidget {
  const CaptureIndicator({super.key, this.capture});
  final TrainingCapture? capture;
  @override
  Widget build(BuildContext context) {
    final value = capture;
    if (value == null) return const SizedBox.shrink();
    final chinese = value.owner.repository.profile['locale'] != 'en';
    String text(String zh, String en) => chinese ? zh : en;
    return ListenableBuilder(
      listenable: value,
      builder: (context, _) => QinIconButton(
        tooltip: value.state == 'RECORDING'
            ? text('采集中 · 点击停止', 'Recording · Stop')
            : text('采集已暂停或停止', 'Recording paused or stopped'),
        onPressed: value.finished || value.state == 'STOPPED'
            ? null
            : () async {
                final stop = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(text('停止采集？', 'Stop recording?')),
                    content: Text(
                      text(
                        '已有视频仍会随本次练习保存，可在完成页删除。',
                        'Recorded video will be kept with this practice. You can delete it on the result page.',
                      ),
                    ),
                    actions: [
                      QinTextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(text('取消', 'Cancel')),
                      ),
                      QinFilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(text('停止', 'Stop')),
                      ),
                    ],
                  ),
                );
                if (stop == true) await value.stop();
              },
        icon: Icon(
          value.state == 'RECORDING'
              ? Icons.videocam
              : Icons.videocam_off_outlined,
          color: value.state == 'RECORDING'
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      ),
    );
  }
}

class CaptureResultCard extends StatefulWidget {
  const CaptureResultCard({super.key, required this.c, required this.recordId});
  final AppController c;
  final String recordId;
  @override
  State<CaptureResultCard> createState() => _CaptureResultCardState();
}

class _CaptureResultCardState extends State<CaptureResultCard> {
  Timer? timer;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(widget.c.captures.open().catchError((_) {}));
    timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final s = widget.c.captures, r = s.forRecord(widget.recordId);
      if (!busy &&
          r != null &&
          r['received'] == true &&
          !captureTerminalStates.contains(r['state']) &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        await run(() => s.refresh(r['capture_id'] as String));
      }
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.c.text(
                '操作暂未完成，请连接原训练档案后重试。',
                'Please connect the original profile and retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c, service = widget.c.captures;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final row = service.forRecord(widget.recordId);
        if (row == null || row['state'] == 'DELETED') {
          return const SizedBox.shrink();
        }
        final id = row['capture_id'] as String;
        final remote = row['remote'] as Map?;
        final label = switch (row['state']) {
          'UPLOADING' => c.text('正在上传视频', 'Uploading video'),
          'REVIEW_REQUIRED' => c.text('等待 Web 端复核', 'Awaiting Web review'),
          'PENDING' ||
          'PROCESSING' ||
          'RUNNING' => c.text('正在处理面部视频', 'Processing face video'),
          'SUCCESS' => c.text('面部分析已完成', 'Face analysis complete'),
          'PARTIAL_SUCCESS' => c.text('部分片段分析完成', 'Some segments analyzed'),
          'NO_VALID_SEGMENTS' => c.text(
            '没有适合分析的面部片段',
            'No suitable face segments',
          ),
          'WAITING_LOGIN' => c.text(
            '请连接训练档案后继续',
            'Connect your training profile to continue',
          ),
          'FAILED' => c.text('面部分析未完成', 'Face analysis unsuccessful'),
          'WAITING_NETWORK' => c.text('等待 Wi-Fi 上传', 'Waiting for Wi-Fi'),
          'SEALING' => c.text('正在整理视频', 'Preparing video'),
          'CANCELLED' => c.text('删除请求待同步', 'Deletion pending'),
          _ => c.text('视频待提交', 'Video pending'),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: QinPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.text('面部分析', 'Face analysis'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(label),
                if (row['message'] != null) Text('${row['message']}'),
                if (remote?['error'] != null) Text('${remote!['error']}'),
                if (row['capture_error'] != null)
                  Text('${row['capture_error']}'),
                if (service.progress[id] != null && row['state'] == 'UPLOADING')
                  LinearProgressIndicator(value: service.progress[id]),
                if (remote?['summary'] != null) Text('${remote!['summary']}'),
                if (remote?['results'] is List &&
                    (remote!['results'] as List).isNotEmpty)
                  ExpansionTile(
                    title: Text(c.text('查看分析详情', 'View analysis')),
                    children: [
                      Text(
                        c.text(
                          '以下为片段模型输出，不代表病情或真实情绪。',
                          'Segment model outputs do not represent a diagnosis or a confirmed emotional state.',
                        ),
                      ),
                      for (final r in remote['results'] as List)
                        ListTile(
                          title: Text(
                            '${r['predicted_class'] ?? r['dominant_tag'] ?? '—'}',
                          ),
                          subtitle: Text(
                            '${r['model_name'] ?? ''} ${r['model_version'] ?? ''}\n${r['tag_distribution'] ?? ''}',
                          ),
                        ),
                    ],
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    if ({'FAILED', 'PARTIAL_SUCCESS'}.contains(row['state']) &&
                        row['received'] == true &&
                        remote?['media_deleted'] != true)
                      QinTextButton(
                        onPressed: busy
                            ? null
                            : () => run(() => service.retryAnalysis(id)),
                        child: Text(c.text('重试分析', 'Retry analysis')),
                      ),
                    QinTextButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              if (!service.connected) {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        CloudIntegrationPage(controller: c),
                                  ),
                                );
                              }
                              if (!mounted) return;
                              if (row['received'] == true) {
                                await service.refresh(id);
                                return;
                              }
                              var mobile = false;
                              if (await service.metered()) {
                                if (!context.mounted) return;
                                mobile =
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          c.text(
                                            '使用移动网络上传？',
                                            'Upload using mobile data?',
                                          ),
                                        ),
                                        content: Text(
                                          c.text(
                                            '录像可能消耗较多流量。',
                                            'Video uploads may use significant data.',
                                          ),
                                        ),
                                        actions: [
                                          QinTextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(c.text('取消', 'Cancel')),
                                          ),
                                          QinFilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(c.text('上传', 'Upload')),
                                          ),
                                        ],
                                      ),
                                    ) ??
                                    false;
                                if (!mobile) return;
                              }
                              await service.upload(id, allowMobile: mobile);
                            }),
                      child: Text(
                        c.text(
                          row['received'] == true ? '刷新' : '继续上传',
                          row['received'] == true ? 'Refresh' : 'Upload',
                        ),
                      ),
                    ),
                    QinTextButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    c.text(
                                      '删除本次视频与面部分析？',
                                      'Delete video and face analysis?',
                                    ),
                                  ),
                                  content: Text(
                                    c.text(
                                      '本次练习成绩仍会保留。',
                                      'Your practice record will be retained.',
                                    ),
                                  ),
                                  actions: [
                                    QinTextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text(c.text('取消', 'Cancel')),
                                    ),
                                    QinFilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(c.text('删除', 'Delete')),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) await service.remove(id);
                            }),
                      child: Text(c.text('删除视频', 'Delete video')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CaptureLibraryPage extends StatefulWidget {
  const CaptureLibraryPage({super.key, required this.c});
  final AppController c;
  @override
  State<CaptureLibraryPage> createState() => _CaptureLibraryPageState();
}

class _CaptureLibraryPageState extends State<CaptureLibraryPage> {
  String? error;
  @override
  void initState() {
    super.initState();
    widget.c.captures.open().catchError((_) {
      if (mounted) {
        setState(
          () => error = widget.c.text(
            '视频列表暂不可用，请重试。',
            'Videos are unavailable. Please retry.',
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Scaffold(
      appBar: AppBar(title: Text(c.text('面部采集与上传', 'Face recordings'))),
      body: ListenableBuilder(
        listenable: c.captures,
        builder: (context, _) {
          final rows =
              c.captures.records.values
                  .where(
                    (r) =>
                        r['state'] != 'DELETED' &&
                        r['source_record_id'] != null,
                  )
                  .toList()
                ..sort(
                  (a, b) => (b['created_ms'] as int).compareTo(
                    a['created_ms'] as int,
                  ),
                );
          return QinPageList(
            children: [
              Text(
                c.text(
                  '采集每次默认关闭。待上传录像在本机最多保留 7 天，视频不会发给 AI 问答模型。',
                  'Recording is off by default. Pending videos stay here for up to 7 days and are not sent to the AI chat model.',
                ),
              ),
              if (error != null) Text(error!),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(c.text('暂无采集视频', 'No recordings yet')),
                  ),
                ),
              for (final row in rows) ...[
                const SizedBox(height: 16),
                Text(
                  DateTime.fromMillisecondsSinceEpoch(row['created_ms'] as int)
                      .toLocal()
                      .toString()
                      .substring(0, 16),
                ),
                CaptureResultCard(
                  c: c,
                  recordId: row['source_record_id'] as String,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
