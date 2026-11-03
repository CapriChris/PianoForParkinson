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
import 'sync_service.dart';
import 'sync_store.dart';

class CloudIntegrationPage extends StatefulWidget {
  const CloudIntegrationPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CloudIntegrationPage> createState() => _CloudIntegrationPageState();
}

class _CloudIntegrationPageState extends State<CloudIntegrationPage> {
  final base = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  SyncStore? sidecar;
  RemoteApi? remote;
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
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final dbDir = File(widget.controller.repository.db.path).parent.path;
      final s = SyncStore();
      await s.open(dbDir);
      sidecar = s;
      final saved = await s.get('base_url');
      if (saved != null) base.text = saved;
      final chosen = await s.get('patient_id');
      patients = await s.patients();
      patientId = chosen;
      if (mounted) setState(() {});
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
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> login() => run(() async {
    final service = RemoteApi(base.text);
    final account = await service.login(username.text.trim(), password.text);
    password.clear();
    remote = service;
    await sidecar?.put('base_url', base.text.trim());
    setState(() => status = '已登录：${account['display_name']}。正在获取云端档案…');
    await refreshPatients();
  });

  Future<void> refreshPatients() async {
    final service = remote;
    if (service == null) return;
    var offset = 0;
    final results = <Map<String, dynamic>>[];
    while (true) {
      final data = await service.bootstrap(offset: offset);
      await sidecar?.rememberBootstrap(data);
      results.addAll(
        (data['patients'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      if (data['next_offset'] == null) break;
      offset = data['next_offset'] as int;
      if (offset > 10000) throw const FormatException('患者列表超过当前同步范围，请联系维护人员。');
    }
    staffCount = await sidecar?.staffCount() ?? 0;
    if (mounted) {
      setState(() {
        patients = results.where((p) => p['is_deleted'] != true).toList();
        if (!patients.any((p) => p['id'] == patientId)) patientId = null;
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
    await sidecar?.put('patient_id', id);
    setState(() => status = '已绑定 ${response['name']}，既有本地训练暂未上传。');
  });

  Future<void> sync() => run(() async {
    final service = remote;
    final s = sidecar;
    final id = patientId;
    if (service == null || s == null || id == null) {
      throw const FormatException('先登录、选择并绑定患者。');
    }
    setState(() => status = '正在同步本地记录，请保持网络连接…');
    final result = await CrossClientSync(
      widget.controller.repository,
      service,
      s,
      deviceId: deviceId,
      localProfileId: profileId,
      patientId: id,
    ).syncAll();
    lastSent = result.uploaded;
    setState(
      () => status = result.errors.isEmpty
          ? '已上传 ${result.uploaded} 条新记录，跳过 ${result.skipped} 条。'
          : '已上传 ${result.uploaded} 条；${result.errors.length} 条待重试：${result.errors.take(2).join('；')}',
    );
  });

  Future<void> readCloud() => run(() async {
    final service = remote;
    final s = sidecar;
    final id = patientId;
    if (service == null || s == null || id == null) {
      throw const FormatException('请先登录并选择患者。');
    }
    int offset = 0;
    while (true) {
      final data = await service.patientData(id, offset: offset);
      await s.rememberPatientData(data);
      if (data['next_offset'] == null) break;
      offset = data['next_offset'] as int;
      if (offset > 5000) throw const FormatException('云端记录超过当前同步容量，请分批导出。');
    }
    final records = await s.patientRecords(id);
    setState(() {
      remoteRecordCount = records.length;
      status = '已缓存 ${records.length} 条云端评估/训练记录，独立于本机原始练习数据库。';
    });
  });

  Future<void> showCloudRecords() async {
    final id = patientId;
    final s = sidecar;
    if (id == null || s == null) {
      setState(() => status = '请先选择患者。');
      return;
    }
    final records = await s.patientRecords(id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
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
                      title: Text('${record['kind']}'),
                      subtitle: Text('记录 ${data['id']}'),
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
      ),
    );
  }

  void openExpert() {
    final service = remote;
    if (service == null) {
      setState(() => status = '请先登录，再使用 AI 问答。');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertQuestionPage(api: service, patientId: patientId),
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
    // Access token is only in this widget's RemoteApi object; never persisted.
    remote?.signOut();
    if (sidecar != null) unawaited(sidecar!.db.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('云端数据与 AI 服务')),
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
            onChanged: loading
                ? null
                : (value) => setState(() => patientId = value),
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
            label: const Text('同步本机练习与计划'),
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: loading ? null : openExpert,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('AI 康复问答'),
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

class ExpertQuestionPage extends StatefulWidget {
  const ExpertQuestionPage({super.key, required this.api, this.patientId});
  final RemoteApi api;
  final String? patientId;
  @override
  State<ExpertQuestionPage> createState() => _ExpertQuestionPageState();
}

class _ExpertQuestionPageState extends State<ExpertQuestionPage> {
  final input = TextEditingController();
  final turns = <({String question, String answer})>[];
  bool busy = false;
  String? error;
  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.ask(text, patientId: widget.patientId);
      if (!mounted) return;
      setState(() {
        turns.add((question: text, answer: '${result['answer']}'));
        input.clear();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 康复问答')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('用于康复知识与平台使用帮助。当前不会向模型传送患者病历，也不会提供诊断和处方。'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final t in turns) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(t.question),
                      ),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(t.answer),
                    ),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '输入康复问题或训练操作疑问',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: '发送',
                  onPressed: busy ? null : send,
                ),
              ],
            ),
          ),
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
      player = VideoPlayerController.file(File(file.path));
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
