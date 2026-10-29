import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart';
import '../domain/contracts.dart';
import '../ui/text_scale.dart';
import '../ui/qin_theme.dart';
import '../ui/qin_components.dart';
import '../domain/task_engine.dart';
import '../domain/cognitive_tasks.dart';
import 'cognitive_cue.dart';
import 'keyboard.dart';
import 'key_duration_guide.dart';
import 'rhythm_timeline.dart';
import 'response_countdown.dart';

class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.c, required this.taskId});
  final AppController c;
  final String taskId;
  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  AppController get c => widget.c;
  bool ready = false, started = false, starting = false, navigated = false;
  bool allowLeave = false, ending = false, orientationRequested = false;
  Animation<double>? routeAnimation;
  String? error;
  final outsidePointers = <int>{};
  Json outsideCoordinates(PointerEvent event) {
    final rect = c.layout!['keyboard_rect'] as List;
    return {
      'x_norm':
          ((event.position.dx - rect[0] / 1000) / (rect[2] / 1000) * 1000000)
              .round(),
      'y_norm':
          ((event.position.dy - rect[1] / 1000) / (rect[3] / 1000) * 1000000)
              .round(),
      'raw_timestamp_us': event.timeStamp.inMicroseconds,
      'device_kind': 'TOUCH',
      'layout_snapshot_id': c.layout!['snapshot_id'],
    };
  }

  void outsideDown(PointerDownEvent event) {
    if (!started ||
        c.layout == null ||
        c.engine!.phase == 'paused' ||
        c.engine!.ended) {
      return;
    }
    final rect = c.layout!['keyboard_rect'] as List;
    final inside =
        event.position.dx >= rect[0] / 1000 &&
        event.position.dx < (rect[0] + rect[2]) / 1000 &&
        event.position.dy >= rect[1] / 1000 &&
        event.position.dy < (rect[1] + rect[3]) / 1000;
    if (!inside) {
      outsidePointers.add(event.pointer);
      c.down(event.pointer, null, coordinates: outsideCoordinates(event));
    }
  }

  void outsideUp(PointerEvent event, bool cancel) {
    if (outsidePointers.remove(event.pointer)) {
      c.up(
        event.pointer,
        cancel: cancel,
        coordinates: outsideCoordinates(event),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    enterTrainingDisplay();
    c.addListener(updated);
    c.trainingUpdates.addListener(updated);
  }

  Future<void> enterTrainingDisplay() async {
    try {
      await c.platform.call('setTrainingFullscreen', {'enabled': true});
      if (!mounted) return;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      orientationRequested = true;
      markReady();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != routeAnimation) {
      routeAnimation?.removeStatusListener(routeStatus);
      routeAnimation = animation;
      routeAnimation?.addStatusListener(routeStatus);
    }
    if (orientationRequested &&
        (routeAnimation == null ||
            routeAnimation!.status == AnimationStatus.completed)) {
      ready = true;
    }
  }

  void routeStatus(AnimationStatus status) => markReady();
  void markReady() {
    if (mounted &&
        !ready &&
        orientationRequested &&
        (routeAnimation == null ||
            routeAnimation!.status == AnimationStatus.completed)) {
      setState(() => ready = true);
    }
  }

  void updated() {
    if (!mounted) return;
    if (started && c.saved && !navigated) {
      navigated = true;
      c.repository.detail(c.engine!.id).then((record) {
        if (mounted && record != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ResultPage(c: c, record: record),
            ),
          );
        }
      });
    }
    setState(() {});
  }

  Future<void> keyboardLayout(Json layout) async {
    if (!ready ||
        starting ||
        layout['canvas_width_dp'] <= layout['canvas_height_dp']) {
      return;
    }
    if (!started) {
      starting = true;
      try {
        await c.start(
          widget.taskId,
          layout,
          reader: MediaQuery.of(context).accessibleNavigation,
        );
        if (mounted) setState(() => started = true);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
      starting = false;
    } else if (c.layout?['snapshot_id'] != layout['snapshot_id']) {
      c.reconfigureLayout(layout);
    }
  }

  Future<void> goHome() async {
    if (!mounted) return;
    setState(() {
      allowLeave = true;
      navigated = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) HomePage.returnHome(context, c);
  }

  Future<void> leaveEndedPractice() async {
    if (c.hasPendingSave &&
        !await confirm(
          context,
          c.text('还有记录未保存，退出练习？', 'Leave with unsaved records?'),
          c.text(
            '已保存的部分会保留。未保存的部分会暂留内存，可在首页重试；关闭应用后这部分可能丢失。',
            'Saved items remain. Unsaved items stay in memory for retrying on Home; closing the app may lose them.',
          ),
        )) {
      navigated = false;
      return;
    }
    await goHome();
  }

  Future<void> endPractice({bool home = false}) async {
    if (ending) return;
    ending = true;
    try {
      if (c.engine!.phase != 'paused') c.pause('USER');
      if (!await confirm(
        context,
        c.text('结束本次练习？', 'End this practice?'),
        c.text('已完成的部分将尝试保存。', 'We will try to save the completed items.'),
      )) {
        return;
      }
      if (home) navigated = true;
      await c.exit();
      if (mounted && home) await leaveEndedPractice();
    } finally {
      ending = false;
    }
  }

  Future<void> back() async {
    if (!started) {
      Navigator.pop(context);
      return;
    }
    if (c.engine!.ended) {
      await leaveEndedPractice();
      return;
    }
    await endPractice(home: true);
  }

  @override
  void dispose() {
    routeAnimation?.removeStatusListener(routeStatus);
    c.removeListener(updated);
    c.trainingUpdates.removeListener(updated);
    unawaited(
      c.platform
          .call('setTrainingFullscreen', {'enabled': false})
          .catchError((_) => <String, dynamic>{}),
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Widget pauseMenu(TaskEngine task) => Column(
    key: const ValueKey('pause-menu'),
    children: [
      Text(
        c.text('练习已暂停', 'Practice paused'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (c.storageError != null)
        Text(
          c.text(
            '尚未全部保存，可重试保存或点击左上角返回退出。',
            'Not fully saved. Retry saving or use the back arrow to leave.',
          ),
        ),
      if (task.pauseReason == 'E_LAYOUT_CHANGED')
        Text(
          c.text(
            '布局改变，本组将重新开始。已完成记录保留。',
            'The layout changed. This block will restart; completed records stay.',
          ),
        ),
      if (task.pauseReason == 'INVALID_FRAME_LATE')
        Text(c.text('画面提示有延迟，请重试。', 'The cue was delayed. Please retry.')),
      if (task.pauseReason == 'E_FRAME_STALLED')
        Text(
          c.text(
            '画面曾停止更新，已暂停并停止声音；未完成项不计零分。',
            'The display stopped updating. Practice and audio paused; unfinished items are not scored as zero.',
          ),
        ),
      if (task.errors.unstable)
        Text(
          c.text(
            '当前设备暂时无法稳定完成这项练习。你可以结束本次，或再次尝试。',
            'This device is having repeated difficulties. You can end this practice or try again.',
          ),
        ),
      const SizedBox(height: 4),
      Wrap(
        // Keep the inline controls above the keyboard in short landscapes.
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          FilledButton.icon(
            key: const ValueKey('resume-practice'),
            onPressed: c.busy || task.ended ? null : () => c.resume(),
            icon: const Icon(Icons.play_arrow),
            label: Text(c.text('继续练习', 'Continue practice')),
          ),
          if (c.storageError != null)
            FilledButton(
              onPressed: c.flush,
              child: Text(c.text('重试保存', 'Retry saving')),
            ),
          OutlinedButton(
            key: const ValueKey('replay-demo'),
            onPressed:
                task.taskId == 'G3_SWITCH' ||
                    task.dual ||
                    task.finishingPhrase ||
                    c.busy
                ? null
                : () => c.resume(replay: true),
            child: Text(c.text('重看演示', 'Replay demo')),
          ),
          if (task.block['status'] != 'COMPLETED')
            OutlinedButton(
              key: const ValueKey('lower-difficulty'),
              onPressed: c.busy || task.level <= 1
                  ? null
                  : () => c.resume(lower: true),
              child: Text(c.text('降低难度', 'Lower difficulty')),
            ),
          if (task.block['status'] != 'COMPLETED')
            OutlinedButton(
              key: const ValueKey('more-help'),
              onPressed: (task.memory || task.taskId == 'G3_SWITCH') && !c.busy
                  ? () => c.resume(help: true)
                  : null,
              child: Text(c.text('增加帮助', 'More help')),
            ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.qin.error,
              side: BorderSide(color: context.qin.error),
            ),
            onPressed: () => endPractice(),
            child: Text(c.text('结束本次', 'End practice')),
          ),
        ],
      ),
    ],
  );
  Widget itemCounter(
    TaskEngine task, {
    bool compact = false,
    TextStyle? style,
  }) {
    final separator = compact ? '/' : ' / ';
    return Text(
      c.text(
        '第 ${task.slot + 1} 组 · ${task.currentItemNumber}$separator${task.planned} 项',
        'Block ${task.slot + 1} · ${task.currentItemNumber}$separator${task.planned} items',
      ),
      style: style,
    );
  }

  Widget ruleHeader(TaskEngine task) => Text(
    c.text(
      task.displayedRule == 'POSITION' ? '规则 A · 按位置' : '规则 B · 按图形',
      task.displayedRule == 'POSITION'
          ? 'Rule A · Match position'
          : 'Rule B · Match shape',
    ),
    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
  );

  Widget recordedItem(TaskEngine task, {bool nextBlock = false}) => Column(
    key: const ValueKey('recorded-item-feedback'),
    children: [
      if (task.taskId == 'G3_SWITCH' && task.phase == 'intertrial') ...[
        ruleHeader(task),
        const SizedBox(height: 4),
      ],
      Text(
        c.text('已记录', 'Recorded'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      itemCounter(task),
      if (nextBlock) ...[
        const SizedBox(height: 12),
        FilledButton(
          onPressed: c.next,
          child: Text(c.text('开始下一组', 'Next block')),
        ),
      ],
    ],
  );

  Widget instructions(TaskEngine? task) {
    if (error != null) {
      return Text(
        c.hasPendingSave
            ? c.text(
                '上次练习还有未保存记录，请返回首页重试保存。',
                'Retry saving your last practice on Home before starting again.',
              )
            : c.text('无法开始，请返回后重试。', 'Unable to start. Go back and retry.'),
      );
    }
    if (task == null) {
      return Text(c.text('正在准备练习…', 'Preparing your practice…'));
    }
    if (task.phase == 'paused') return pauseMenu(task);
    if (task.ended) {
      return Column(
        children: [
          Text(
            c.storageError == null
                ? c.text('正在保存本次记录…', 'Saving your practice…')
                : c.text(
                    '尚未全部保存，可重试或点击左上角返回退出。',
                    'Not fully saved. Retry or use the back arrow to leave.',
                  ),
          ),
          if (c.storageError != null)
            FilledButton(
              onPressed: c.finishSave,
              child: Text(c.text('重试保存', 'Retry saving')),
            ),
        ],
      );
    }
    if (task.phase == 'feedback') {
      return recordedItem(task, nextBlock: true);
    }
    if (task.phase == 'trialFeedback' ||
        task.phase == 'intertrial' ||
        task.memoryResponseCollected) {
      return recordedItem(task);
    }
    if (task.rhythm) {
      final guidance = task.leadInBeat != null
          ? c.text('跟随预备拍，准备好', 'Get ready with the count in')
          : task.phase == 'demo' || task.phase == 'gap'
          ? c.text('先看、先听，暂时不用按键', 'Watch and listen; no press yet')
          : task.finishingPhrase
          ? c.text('让最后一拍走完', 'Let the final beat finish')
          : task.durationTooShort
          ? c.text('时值不足 · 跟随下一音继续', 'Too short · Continue with the next note')
          : {
              'cue',
              'beatPrepare',
              'response',
              'holdTail',
              'release',
            }.contains(task.phase)
          ? c.text('按住琴键，条满后松开', 'Hold the key; release when the bar fills')
          : c.text('准备好，跟随下一拍', 'Get ready for the next beat');
      return Column(
        children: [
          RhythmTimeline(task: task, chinese: c.chinese),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 4,
            children: [
              Text(
                guidance,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20),
              ),
              itemCounter(
                task,
                compact: true,
                style: const TextStyle(fontSize: 20),
              ),
            ],
          ),
        ],
      );
    }
    if (task.dual) {
      return Column(
        children: [
          Text(
            switch (task.phase) {
              'waiting' => c.text('即将开始', 'Starting soon'),
              'countdown' => '${task.countdown}',
              'cue' || 'response' => c.text(
                '左区 ${task.expected[0] + 1} 号键 · 右区 ${task.expected[1] + 1} 号键',
                'Left key ${task.expected[0] + 1} · Right key ${task.expected[1] + 1}',
              ),
              _ => c.text('准备下一项', 'Getting ready for the next item'),
            },
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: task.phase == 'countdown' ? 36 : 22,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (task.responding)
            Text(c.text('同时按下两琴键', 'Press both keys at the same time')),
          if (task.responseRemainingUs != null)
            ResponseCountdown(
              remainingUs: task.responseRemainingUs!,
              fraction: task.responseFraction,
              chinese: c.chinese,
            ),
          itemCounter(task, style: const TextStyle(fontSize: 20)),
        ],
      );
    }
    if (task.windowed) {
      return Column(
        children: [
          if (task.taskId == 'G3_SWITCH') ruleHeader(task),
          if (task.phase == 'cue' || task.phase == 'response')
            if (task.taskId == 'G3_SWITCH')
              SignalSlots(
                position: task.target['r'] as int,
                shape: task.target['s'] as int,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    task.target['trial_type'] == 'GO'
                        ? c.text(
                            '弹奏 · ${task.expected.single + 1} 号键',
                            'Play · Key ${task.expected.single + 1}',
                          )
                        : c.text('等待 · 不按键', 'Wait · No press'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (task.target['trial_type'] == 'NO_GO')
                    const RestMark()
                  else
                    ShapeMark(shape: task.expected.single, size: 28),
                ],
              )
          else
            Text(
              switch (task.phase) {
                'countdown' => '${task.countdown}',
                'ruleHeader' => c.text('看看本次规则', 'Read the rule'),
                'intertrial' => c.text('已记录', 'Recorded'),
                _ => c.text('即将开始', 'Starting soon'),
              },
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: task.phase == 'countdown' ? 36 : 22,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 4,
            children: [
              if (task.responding &&
                  task.requiresHold &&
                  (task.target['trial_type'] != 'NO_GO' ||
                      task.durationTooShort))
                Text(
                  c.text(
                    task.durationTooShort ? '时值不足 · 等待下一项' : '按住琴键，条满后松开',
                    task.durationTooShort
                        ? 'Too short · Wait for the next signal'
                        : 'Hold the key; release when the bar fills',
                  ),
                  style: const TextStyle(fontSize: 20),
                ),
              itemCounter(task, style: Theme.of(context).textTheme.bodySmall),
              if (task.showAnswer &&
                  task.taskId == 'G3_SWITCH' &&
                  task.responding)
                Text(
                  c.text(
                    '提示：${task.expected.single + 1} 号键',
                    'Hint: key ${task.expected.single + 1}',
                  ),
                  style: TextStyle(fontSize: 20, color: context.qin.primary),
                ),
            ],
          ),
          if (task.responseRemainingUs != null)
            ResponseCountdown(
              remainingUs: task.responseRemainingUs!,
              fraction: task.responseFraction,
              chinese: c.chinese,
            ),
        ],
      );
    }
    return Column(
      children: [
        Text(
          switch (task.phase) {
            'waiting' => c.text('即将开始', 'Starting soon'),
            'countdown' => '${task.countdown}',
            'demo' || 'gap' => c.text('先看，先听', 'Watch and listen'),
            'release' when task.memory => c.text('请松开琴键', 'Release the keys'),
            'response' || 'cue' || 'release' =>
              task.memory
                  ? c.text('轮到你 · 按顺序弹奏', 'Your turn · Play the sequence')
                  : c.text(
                      '轮到你 · 弹奏 ${task.expected.single + 1} 号键',
                      'Your turn · Play key ${task.expected.single + 1}',
                    ),
            _ => c.text('准备下一项', 'Getting ready for the next item'),
          },
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: task.phase == 'countdown' ? 36 : 22,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        itemCounter(task),
        if (task.showAnswer && task.memory && task.phase == 'response')
          Text(
            task.expected.map((k) => '${k + 1}').join('  →  '),
            style: TextStyle(color: context.qin.primary),
          ),
        if (task.memory && task.responseRemainingUs != null)
          ResponseCountdown(
            remainingUs: task.responseRemainingUs!,
            fraction: task.responseFraction,
            chinese: c.chinese,
          ),
        if (task.requiresHold && task.durationTooShort)
          Text(
            c.text('时值不足，请重新按住当前音', 'Too short. Hold this note again'),
            style: TextStyle(
              color: context.qin.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (task.requiresHold &&
            task.memory &&
            task.phase == 'response' &&
            !task.durationTooShort)
          Text(
            c.text('按住琴键，条满后松开', 'Hold the key; release when the bar fills'),
            style: const TextStyle(fontSize: 20),
          ),
        if (task.taskId == 'S1_GUIDED' &&
            task.responding &&
            !task.durationTooShort)
          Text(
            c.text('按住琴键，条满后松开；短按请重试', 'Hold the key; retry short presses'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.framePresented();
    });
    final task = started ? c.engine : null;
    if (task?.phase == 'cue') {
      final attempt = task!.attempts.last['attempt_id'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            c.engine?.attempts.last['attempt_id'] == attempt &&
            c.engine?.phase == 'cue') {
          c.cue();
        }
      });
    }
    final paused = task?.phase == 'paused';
    return PopScope(
      canPop: !started || allowLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: max(
            60.0,
            MediaQuery.textScalerOf(context).scale(24) * 1.3 + 12,
          ),
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: back,
            tooltip: c.text('返回', 'Back'),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            taskTitle(widget.taskId, c.chinese),
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontSize: 24),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!paused)
              TextButton.icon(
                key: const ValueKey('pause-toggle'),
                style: TextButton.styleFrom(
                  backgroundColor: paused ? context.qin.primary : null,
                  foregroundColor: paused
                      ? context.qin.onPrimary
                      : context.qin.primary,
                ),
                onPressed: !started || c.busy || task!.ended
                    ? null
                    : () {
                        if (paused) {
                          c.resume();
                        } else {
                          c.pause('USER');
                        }
                      },
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(
                  paused ? c.text('继续', 'Continue') : c.text('暂停', 'Pause'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, size) {
              final alternate = widget.taskId == 'M1_ALTERNATE';
              final count = isDualTask(widget.taskId)
                  ? 6
                  : alternate
                  ? 2
                  : MediaQuery.sizeOf(context).width < 600
                  ? 5
                  : 7;
              final keyboardWidth = alternate
                  ? min(520.0, size.maxWidth - 32)
                  : null;
              final fits =
                  (!isDualTask(widget.taskId) || size.maxWidth >= 600) &&
                  size.maxWidth - 32 >= count * 60 + (count - 1) * 8 &&
                  size.maxHeight >= 200;
              if (!fits && started && !task!.ended && !paused) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) c.pause('E_LAYOUT_SMALL');
                });
              }
              if (!fits) {
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: task != null
                              ? instructions(task)
                              : Text(
                                  c.text(
                                    '请横放设备或扩大窗口，让琴键有足够空间。',
                                    'Rotate the device or enlarge the window so the keys have enough space.',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              final scaledToolbar = max(
                60.0,
                MediaQuery.textScalerOf(context).scale(24) * 1.3 + 12,
              );
              final musicToolbar = max(
                60.0,
                musicTextScalerOf(context).scale(24) * 1.3 + 12,
              );
              final keyHeight = practiceKeyHeight(
                size.maxHeight + scaledToolbar - musicToolbar,
              );
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: outsideDown,
                onPointerUp: (event) => outsideUp(event, false),
                onPointerCancel: (event) => outsideUp(event, true),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: task?.rhythm == true
                                  ? instructions(task)
                                  : QinPanel(
                                      soft: true,
                                      padding: const EdgeInsets.all(8),
                                      child: instructions(task),
                                    ),
                            ),
                          ),
                        ),
                        if (task?.hasDurationGuide ??
                            (widget.taskId == 'G1_MEMORY' ||
                                widget.taskId == 'S1_GUIDED' ||
                                isBeatTask(widget.taskId)))
                          SizedBox(
                            width: keyboardWidth,
                            child: KeyDurationGuide(
                              count: count,
                              targetKey: task?.durationGuide?.key,
                              progress: task?.durationGuide?.progress ?? 0,
                              durationMs: task == null
                                  ? 400
                                  : task.noteDurationUs ~/ 1000,
                              paused: paused,
                              tooShort: task?.durationTooShort ?? false,
                            ),
                          ),
                        IgnorePointer(
                          ignoring: c.busy || paused || task?.ended == true,
                          child: ExcludeSemantics(
                            excluding: paused || task?.ended == true,
                            child: SizedBox(
                              width: keyboardWidth,
                              height: keyHeight,
                              child: RepaintBoundary(
                                child: PianoKeyboard(
                                  key: ValueKey(ready),
                                  count: count,
                                  active: isDualTask(widget.taskId)
                                      ? const {0, 1, 2, 3, 4, 5}
                                      : alternate
                                      ? const {0, 1}
                                      : isCognitiveTask(widget.taskId)
                                      ? const {0, 1, 2}
                                      : const {0, 1, 2, 3, 4},
                                  locked:
                                      paused || (task?.inputLocked ?? false),
                                  highlighted: task?.highlighted,
                                  demonstratingKeys:
                                      !paused &&
                                          task?.phase == 'demo' &&
                                          task?.highlighted != null
                                      ? {task!.highlighted!}
                                      : const {},
                                  demonstrationPulse: (
                                    task?.id,
                                    task?.generation,
                                    task?.demonstrationStep,
                                  ),
                                  highlightedKeys:
                                      task?.dual == true &&
                                          (task!.phase == 'cue' ||
                                              task.phase == 'response')
                                      ? task.expected.toSet()
                                      : const {},
                                  showShapes: widget.taskId == 'G3_SWITCH',
                                  textScale:
                                      (musicTextScalerOf(context).scale(1) *
                                              1000)
                                          .round(),
                                  onLayout: keyboardLayout,
                                  onDown: (p, k, d, xy) {
                                    if (started) {
                                      c.down(
                                        p,
                                        k,
                                        disabled: d,
                                        coordinates: xy,
                                      );
                                    }
                                  },
                                  onUp: (p, k, cancel, xy) {
                                    if (started) {
                                      c.up(p, cancel: cancel, coordinates: xy);
                                    }
                                  },
                                  onMove: (p, xy) {
                                    if (started) c.move(p, xy);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
