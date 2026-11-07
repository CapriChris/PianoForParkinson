/// A deliberately separate cloud surface. All existing training pages and
/// local-first audio engines remain untouched.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../app/app_controller.dart';
import 'remote_api.dart';
import 'sync_store.dart';

class CloudIntegrationPage extends StatefulWidget {
  const CloudIntegrationPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CloudIntegrationPage> createState() => _CloudIntegrationPageState();
}

class _CloudIntegrationPageState extends State<CloudIntegrationPage>
    with WidgetsBindingObserver {
  final base = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  SyncStore? sidecar;
  RemoteApi? get remote => widget.controller.cloudSync.remote;
  List<Map<String, dynamic>> cloudRecords = [];
  final kinds = const {
    'assessment_sessions': '评估',
    'piano_sessions': '钢琴训练',
    'guided_song_sessions': '曲目跟弹',
    'pose_sessions': '动作训练',
    'training_plans': '训练计划',
    'micro_expression_results': '面部分析',
    'finger_tapping_results': '手指敲击',
    'functional_assessments': '功能评估',
    'external_practice_records': '软件训练记录',
  };
  List<Map<String, dynamic>> patients = [];
  String? patientId;
  String status = '登录后选择患者并绑定，既有本地练习不会被修改。';
  bool loading = false;
  int? lastSent;
  int remoteRecordCount = 0;
  int staffCount = 0;

  String get profileId =>
      widget.controller.repository.profile['profile_id'] as String;
  String get deviceId =>
      widget.controller.settings['device_local_id'] as String;
  String get patientName {
    for (final p in patients) {
      if (p['id'] == patientId) return '${p['name']}（${p['hospital_number']}）';
    }
    return '尚未选择';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.cloudSync.cloud.addListener(_cloudChanged);
    unawaited(_load());
  }

  void _cloudChanged() {
    if (!mounted) return;
    setState(() {
      final coordinator = widget.controller.cloudSync;
      cloudRecords =
          remote?.signedIn == true && patientId == coordinator.patient
          ? coordinator.cloud.value
          : [];
      remoteRecordCount = cloudRecords.length;
      if (remote?.signedIn != true) {
        patients = [];
        patientId = null;
      }
    });
  }

  Future<void> _load() async {
    try {
      final s = await widget.controller.cloudSync.store();
      if (!mounted) return;
      final saved = await s.get('base_url');
      if (!mounted) return;
      sidecar = s;
      base.text =
          remote?.base.toString() ??
          saved ??
          'https://ccqspace.site/pd-rehab/api';
      patientId = widget.controller.cloudSync.patient;
      setState(() {});
      if (remote?.signedIn == true) await run(_refreshCloud);
    } catch (e) {
      if (mounted) setState(() => status = '同步存储初始化失败：$e');
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (loading) return;
    setState(() => loading = true);
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is RemoteApiException && (e.status == 401 || e.status == 403)) {
            widget.controller.cloudSync.signOut();
            patients = [];
            patientId = null;
            cloudRecords = [];
            remoteRecordCount = 0;
          }
          status = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> login() => run(() async {
    final coordinator = widget.controller.cloudSync;
    widget.controller.captures.disconnect();
    coordinator.signOut();
    setState(() {
      patients = [];
      patientId = null;
      cloudRecords = [];
      remoteRecordCount = 0;
    });
    final service = RemoteApi(base.text);
    final account = await service.login(username.text.trim(), password.text);
    if (!mounted) {
      service.signOut();
      return;
    }
    password.clear();
    await coordinator.signIn(
      service,
      account['id'] as String,
      deviceId,
      profileId,
    );
    if (!mounted) return;
    widget.controller.captures.connect(service, account['id'] as String);
    if (coordinator.patient != null && coordinator.bindingId != null) {
      widget.controller.captures.bind(
        coordinator.patient!,
        coordinator.bindingId!,
      );
    }
    await sidecar?.put('base_url', service.base.toString());
    if (!mounted) return;
    patientId = coordinator.patient;
    await _refreshCloud();
  });

  Future<void> _refreshCloud() async {
    await refreshPatients();
    if (!mounted) return;
    if (patientId != null && patientId == widget.controller.cloudSync.patient) {
      widget.controller.cloudSync.trigger();
      await _readCloud();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        remote?.signedIn == true &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(run(_refreshCloud));
    }
  }

  Future<void> refreshPatients() async {
    final service = remote;
    if (service == null || !service.signedIn) return;
    var offset = 0;
    final results = <Map<String, dynamic>>[];
    var staff = 0;
    while (true) {
      final data = await service.bootstrap(offset: offset);
      staff = (data['staff'] as List?)?.length ?? 0;
      results.addAll(
        (data['patients'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      if (data['next_offset'] == null) break;
      offset = data['next_offset'] as int;
      if (offset > 10000) throw const FormatException('患者列表超过当前同步范围，请联系维护人员。');
    }
    staffCount = staff;
    if (mounted) {
      setState(() {
        patients = results.where((p) => p['is_deleted'] != true).toList();
        if (!patients.any((p) => p['id'] == patientId)) {
          patientId = null;
          cloudRecords = [];
          remoteRecordCount = 0;
        }
        status = '已取得 ${patients.length} 位可用患者、$staffCount 位工作人员。请确认本机记录归属后绑定。';
      });
    }
  }

  Future<void> bind() => run(() async {
    final service = remote;
    final id = patientId;
    if (service == null || id == null) {
      throw const FormatException('请先登录并选择患者。');
    }
    final response = await service.bindPatient(deviceId, profileId, id);
    await widget.controller.cloudSync.setBinding(
      id,
      response['binding_id'] as String,
    );
    widget.controller.captures.bind(id, response['binding_id'] as String);
    if (mounted) {
      setState(
        () =>
            status = '已绑定 ${response['name']}（${response['hospital_number']}）。',
      );
    }
    await _readCloud();
  });

  Future<void> sync() => run(() async {
    if (patientId != widget.controller.cloudSync.patient) {
      throw const FormatException('请先确认当前患者绑定。');
    }
    final result = await widget.controller.cloudSync.sync();
    if (!mounted) return;
    setState(() {
      lastSent = result.uploaded;
      status = result.errors.isEmpty
          ? '已上传 ${result.uploaded} 条。'
          : '部分记录待重试：${result.errors.first}';
    });
  });

  Future<void> readCloud() => run(_readCloud);

  Future<void> _readCloud() async {
    final service = remote, id = patientId;
    if (service == null || !service.signedIn || id == null) return;
    if (id != widget.controller.cloudSync.patient) {
      throw StateError('请先确认所选档案的绑定。');
    }
    await widget.controller.cloudSync.sync();
    if (widget.controller.cloudSync.legacyServer &&
        mounted &&
        identical(remote, service) &&
        patientId == id) {
      final link = await service.bindPatient(deviceId, profileId, id);
      if (link['binding_id'] != widget.controller.cloudSync.bindingId) {
        throw const RemoteApiException(403, '患者绑定已变化。');
      }
      final data = await service.patientData(id);
      if (!mounted || !identical(remote, service) || patientId != id) return;
      final records = <Map<String, dynamic>>[
        for (final entry in (data['categories'] as Map).entries)
          for (final record in entry.value as List)
            {'kind': entry.key, 'data': record},
      ];
      setState(() {
        cloudRecords = records;
        remoteRecordCount = records.length;
        status = '旧服务器：已读取近期记录，尚未启用增量历史。';
      });
      return;
    }
    _cloudChanged();
  }

  Future<void> showCloudRecords() async {
    final coordinator = widget.controller.cloudSync;
    final api = remote, id = patientId;
    if (api?.signedIn != true || id == null || id != coordinator.patient) {
      setState(() => status = '请先登录并选择患者。');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: coordinator.cloud,
        builder: (context, current, _) {
          final authorized =
              identical(remote, api) &&
              api?.signedIn == true &&
              coordinator.patient == id &&
              patientId == id;
          final records = authorized
              ? (coordinator.legacyServer ? cloudRecords : current)
              : <Map<String, dynamic>>[];
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: .8,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('云端评估与训练记录（只读）'),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        final data = Map<String, dynamic>.from(
                          record['data'] as Map,
                        );
                        return ExpansionTile(
                          title: Text(
                            kinds[record['kind']] ?? '${record['kind']}',
                          ),
                          subtitle: Text(
                            '${data['completed_at'] ?? data['started_at'] ?? data['created_at'] ?? '时间未记录'} · ${data['status'] ?? '历史记录'}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText('${record['data']}'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void openFace() {
    final service = remote;
    final id = patientId;
    if (service == null || id == null) {
      setState(() => status = '请先登录并选择患者，再进行面部分析。');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteFacePage(
          api: service,
          patientId: id,
          profileId: profileId,
          deviceId: deviceId,
          patientName: patientName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    base.dispose();
    username.dispose();
    password.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.cloudSync.cloud.removeListener(_cloudChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('云端数据与面部分析'),
      actions: [
        if (remote?.signedIn == true)
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.controller.captures.disconnect();
              setState(() {
                widget.controller.cloudSync.signOut();
                patients = [];
                patientId = null;
                cloudRecords = [];
                status = '已退出登录。';
              });
            },
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('仅用于联调。请使用测试环境、测试患者和测试素材。原始记录保留在本机。'),
          const SizedBox(height: 16),
          TextField(
            controller: base,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'HTTPS API 地址'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: username,
            decoration: const InputDecoration(labelText: '工作人员账号'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : login,
            icon: const Icon(Icons.login),
            label: const Text('登录并同步患者档案'),
          ),
          ValueListenableBuilder<String>(
            valueListenable: widget.controller.cloudSync.message,
            builder: (context, message, _) {
              final coordinator = widget.controller.cloudSync;
              final signed = coordinator.remote?.signedIn == true;
              return Column(
                children: [
                  SwitchListTile(
                    title: const Text('前台自动同步'),
                    subtitle: Text(
                      message.isEmpty
                          ? '绑定后同步新训练；绑定前的记录留在本机。断网后会在前台重试。'
                          : message,
                    ),
                    value: coordinator.enabled,
                    onChanged:
                        !signed ||
                            loading ||
                            patientId == null ||
                            patientId != coordinator.patient
                        ? null
                        : (value) => unawaited(
                            run(() async {
                              await coordinator.setEnabled(value);
                              if (mounted) setState(() {});
                            }),
                          ),
                  ),
                  if (signed &&
                      coordinator.unconfirmedPlanCount > 0 &&
                      patientId == coordinator.patient)
                    TextButton(
                      onPressed: loading
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('确认既有计划的归属'),
                                  content: Text(
                                    '请确认这 ${coordinator.unconfirmedPlanCount} 份本机旧计划都属于当前患者。只同步这些计划和绑定后的进度，绑定前的训练成绩不会补传。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('确认归属'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true && mounted) {
                                await run(coordinator.confirmExistingPlans);
                              }
                            },
                      child: const Text('确认既有计划归属'),
                    ),
                  if (signed)
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              widget.controller.captures.disconnect();
                              coordinator.signOut();
                              setState(() {
                                patients = [];
                                patientId = null;
                                cloudRecords = [];
                                remoteRecordCount = 0;
                                status = '已退出云端账号。';
                              });
                            },
                      child: const Text('退出云端账号'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: ValueKey('${patients.length}-$patientId'),
            initialValue: patients.any((p) => p['id'] == patientId)
                ? patientId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '本机记录所属患者'),
            items: [
              for (final p in patients)
                DropdownMenuItem<String>(
                  value: p['id'] as String,
                  child: Text(
                    '${p['name']}（${p['hospital_number']}）',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: loading || widget.controller.cloudSync.patient != null
                ? null
                : (value) => setState(() {
                    patientId = value;
                    cloudRecords = [];
                    remoteRecordCount = 0;
                  }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: loading ? null : bind,
            icon: const Icon(Icons.link),
            label: const Text('确认绑定此患者'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : sync,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('立即同步'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : readCloud,
            icon: const Icon(Icons.download_outlined),
            label: const Text('获取云端评估与训练历史'),
          ),
          if (remoteRecordCount > 0)
            TextButton(
              onPressed: showCloudRecords,
              child: Text('查看已缓存的 $remoteRecordCount 条记录'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: loading ? null : openFace,
            icon: const Icon(Icons.face_outlined),
            label: const Text('上传面部视频分析'),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 16),
          SelectableText(status),
          const SizedBox(height: 8),
          const Text('注意：此版本以 Web 患者档案为主、软件上传历史记录；不会覆盖本机原始数据。切换患者不能自动转移旧训练记录。'),
        ],
      ),
    ),
  );
}

class RemoteFacePage extends StatefulWidget {
  const RemoteFacePage({
    super.key,
    required this.api,
    required this.patientId,
    required this.deviceId,
    required this.profileId,
    required this.patientName,
  });
  final RemoteApi api;
  final String patientId, deviceId, profileId, patientName;
  @override
  State<RemoteFacePage> createState() => _RemoteFacePageState();
}

class _RemoteFacePageState extends State<RemoteFacePage> {
  XFile? video;
  VideoPlayerController? player;
  String message = '录制或选择视频后上传，由服务器的真实面部模型分析。';
  bool busy = false;
  String? jobId;
  Map<String, dynamic>? job;
  List<Map<String, dynamic>> candidates = [];
  String? previewedCandidateId;

  Future<void> choose(ImageSource source) async {
    try {
      final file = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      if (file == null) return;
      await player?.dispose();
      player = VideoPlayerController.file(
        File(file.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );
      await player!.initialize();
      setState(() {
        video = file;
        jobId = null;
        job = null;
        candidates = [];
        previewedCandidateId = null;
        message = '视频已选取，请确认后上传。';
      });
    } catch (e) {
      if (mounted) setState(() => message = '无法获取视频：$e');
    }
  }

  Future<void> upload() async {
    if (video == null || busy) return;
    setState(() {
      busy = true;
      message = '正在上传视频…';
    });
    try {
      final result = await widget.api.faceJob(
        video!.path,
        patientId: widget.patientId,
        profileId: widget.profileId,
        deviceId: widget.deviceId,
      );
      jobId = result['job_id'] as String;
      job = result;
      if (result['status'] == 'REVIEW_REQUIRED') {
        final suggested = await widget.api.faceCandidates(jobId!);
        candidates = (suggested['candidates'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        message = candidates.isEmpty
            ? '没有找到合适的候选面部片段，请尝试重新录制。'
            : '请选择候选片段，预览后再确认。';
      } else {
        message = '上传完成。请查询处理结果。';
      }
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(Map<String, dynamic> candidate) async {
    if (jobId == null || busy) return;
    setState(() {
      busy = true;
      message = '正在提交已确认关键帧…';
    });
    try {
      final onset = candidate['onset_frame'] as int;
      final apex = candidate['apex_frame'] as int;
      final offset = candidate['offset_frame'] as int;
      job = await widget.api.reviewFrames(jobId!, onset, apex, offset);
      message = '关键帧已确认，正在分析。';
      candidates.clear();
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> poll() async {
    if (jobId == null || busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.faceStatus(jobId!);
      job = result;
      message = result['status'] == 'SUCCESS'
          ? '分析完成'
          : result['status'] == 'FAILED'
          ? '${result['message'] ?? '分析失败'}'
          : '状态：${result['status']}';
    } catch (e) {
      message = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showCandidate(Map<String, dynamic> candidate) async {
    final target = ((candidate['apex_time'] as num?)?.toDouble() ?? 0) * 1000;
    await player?.seekTo(Duration(milliseconds: target.round()));
    await player?.pause();
    if (mounted) setState(() => previewedCandidateId = '${candidate['id']}');
  }

  @override
  void dispose() {
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('面部视频分析')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('当前患者：${widget.patientName}'),
          const Text('上传前请确认已获得患者对面部视频采集和远程处理的同意。'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : () => choose(ImageSource.camera),
                icon: const Icon(Icons.videocam),
                label: const Text('录制视频'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => choose(ImageSource.gallery),
                icon: const Icon(Icons.video_library),
                label: const Text('选择视频'),
              ),
            ],
          ),
          if (player != null && player!.value.isInitialized) ...[
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: player!.value.aspectRatio,
              child: VideoPlayer(player!),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy || video == null ? null : upload,
            child: const Text('确认上传并分析'),
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('候选关键帧需人工确认（起始/峰值/结束）。点击预览定位后再提交。'),
            for (final candidate in candidates)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        '候选：${candidate['onset_frame']} / ${candidate['apex_frame']} / ${candidate['offset_frame']} 帧',
                      ),
                      subtitle: Text('峰值位置约 ${candidate['apex_time']} 秒'),
                      onTap: () => showCandidate(candidate),
                    ),
                    TextButton(
                      onPressed:
                          busy || previewedCandidateId != '${candidate['id']}'
                          ? null
                          : () => review(candidate),
                      child: const Text('我已核对视频，确认这一组关键帧'),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          if (jobId != null)
            OutlinedButton(
              onPressed: busy ? null : poll,
              child: const Text('刷新分析结果'),
            ),
          if (busy) const LinearProgressIndicator(),
          Text(message),
          if (job?['result'] != null) SelectableText('模型结果：${job!['result']}'),
        ],
      ),
    ),
  );
}
