import '../ui/qin_dialog.dart';
import 'capture_widgets.dart';
import '../ui/qin_press.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/piano_app.dart' show HomePage;
import '../data/training_schedule_repository.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../domain/history.dart' show recordDateLabel;
import '../ui/metric_visuals.dart' show MetricRingPainter;
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import 'assistant_page.dart';
import 'dance_player_page.dart';

class DanceResultPage extends StatefulWidget {
  const DanceResultPage({
    super.key,
    required this.c,
    required this.record,
    this.saveRecord,
    this.alreadySaved = false,
    this.showAssistant = true,
  });
  final AppController c;
  final Json record;
  final Future<void> Function(Json)? saveRecord;
  final bool alreadySaved;
  final bool showAssistant;
  @override
  State<DanceResultPage> createState() => _DanceResultPageState();
}

class _DanceResultPageState extends State<DanceResultPage> {
  bool saving = false, allowLeave = false;
  late bool saved = widget.alreadySaved;
  AppController get c => widget.c;
  @override
  void initState() {
    super.initState();
    if (!saved) unawaited(save());
  }

  Future<void> save() async {
    if (saving || saved) return;
    setState(() => saving = true);
    try {
      if (widget.saveRecord != null) {
        await widget.saveRecord!(widget.record);
      } else {
        await TrainingScheduleRepository(
          c.repository.db,
          c.repository.profile['profile_id'] as String,
        ).saveDance(widget.record);
      }
      unawaited(c.captures.recordSaved(widget.record['session_id'] as String));
      c.syncPlanReminders();
      if (mounted) setState(() => saved = true);
      if (widget.saveRecord == null) {
        c.cloudSync.trigger();
        unawaited(c.refreshHistory());
      }
    } catch (_) {
      /* The same immutable session remains available for retry. */
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> leave({bool home = false}) async {
    if (saving) return;
    if (!saved) {
      final exit = await showDialog<bool>(
        context: context,
        builder: (context) => QinDialog(
          title: Text(c.text('记录尚未保存', 'Record not saved')),
          content: Text(
            c.text('离开会丢失本次未保存的记录。', 'Leaving will lose this unsaved record.'),
          ),
          actions: [
            QinTextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.text('返回重试', 'Retry saving')),
            ),
            QinFilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(c.text('离开', 'Leave')),
            ),
          ],
        ),
      );
      if (exit != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => allowLeave = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (home) {
      HomePage.returnHome(context, c);
    } else {
      Navigator.pop(context);
    }
  }

  Widget summary(List<Json> parts) {
    final completed = parts.where((p) => p['reached_end'] == true).length;
    final fraction = parts.isEmpty ? null : completed / parts.length;
    final ring = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 112,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: MetricRingPainter(
                    fraction,
                    context.qin.primary,
                    context.qin.line,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  child: Text(
                    parts.isEmpty ? '—' : '$completed / ${parts.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(c.text('已播完部分', 'Parts completed'), textAlign: TextAlign.center),
      ],
    );
    final duration = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, color: context.qin.primary),
        const SizedBox(height: 12),
        Text(
          c.text('本次播放时长', 'Playback time'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          durationLabel(widget.record['active_ms'] as int),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: context.qin.primary),
        ),
      ],
    );
    return QinPanel(
      backgroundOpacity: .92,
      child: LayoutBuilder(
        builder: (context, bounds) {
          if (bounds.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.5) {
            return Column(
              children: [
                ring,
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                duration,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: ring),
                const VerticalDivider(width: 32),
                Expanded(child: duration),
              ],
            ),
          );
        },
      ),
    );
  }

  String durationLabel(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    if (seconds == 0 && milliseconds > 0) {
      return c.text('不足1秒', 'Less than 1 sec');
    }
    if (seconds < 60) return c.text('$seconds 秒', '$seconds sec');
    return c.text(
      '${seconds ~/ 60} 分 ${seconds % 60} 秒',
      '${seconds ~/ 60} min ${seconds % 60} sec',
    );
  }

  Widget resultHeader(bool short) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (short)
        Row(
          children: [
            QinIconButton(
              onPressed: saving ? null : leave,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.text('完成练习', 'Practice complete'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ],
        )
      else ...[
        Align(
          alignment: Alignment.centerLeft,
          child: QinIconButton(
            onPressed: saving ? null : leave,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        Text(
          c.text('完成练习', 'Practice complete'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ],
      const SizedBox(height: 4),
      Text(
        (widget.record[c.chinese ? 'title_zh' : 'title_en'] ??
                widget.record['title'] ??
                c.text('舞蹈跟练', 'Dance practice'))
            as String,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final parts = List<Json>.from(r['parts'] as List? ?? []);
    final short = qinShortLandscape(context);
    final scrollHeader = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final compactActions =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final actionStyle = compactActions
        ? const ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          )
        : null;
    final artwork =
        qinDanceCourseImage(r['content_id'] as String?)
            ?.replaceAll('.png', '.webp') ??
        (r['content_id'] == null && c.chinese
            ? '37-balance-six-course.webp'
            : '36-practice-dance.webp');
    final started = r['started_utc_ms'];
    final utc = started is int
        ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true)
        : null;
    final offset = r['utc_offset_minutes'];
    final date = utc == null
        ? null
        : recordDateLabel(
            offset is int ? utc.add(Duration(minutes: offset)) : utc.toLocal(),
          );
    return PopScope(
      canPop: saved || allowLeave,
      onPopInvokedWithResult: (popped, result) {
        if (!popped) unawaited(leave());
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!context.qin.highContrast)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.sizeOf(context).height * 2 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/ui_images/$artwork',
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: context.qin.background),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xd9fffaf0),
                              Color(0xaafffaf0),
                              Color(0x22fffaf0),
                            ],
                            stops: [0, .48, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              QinActionPage(
                fixedHeader: scrollHeader ? null : resultHeader(short),
                actions: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: QinFilledButton.icon(
                            key: const ValueKey('dance-practise-again'),
                            style: actionStyle,
                            onPressed: !saved
                                ? null
                                : () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => DancePlayerPage(
                                        c: c,
                                        course:
                                            danceCourses
                                                .where(
                                                  (course) =>
                                                      course.id ==
                                                      r['content_id'],
                                                )
                                                .firstOrNull ??
                                            chineseDanceCourse,
                                        saveRecord: widget.saveRecord,
                                      ),
                                    ),
                                  ),
                            icon: compactActions
                                ? null
                                : const Icon(Icons.replay),
                            label: Text(
                              c.text('再练一次', 'Practice again'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: QinOutlinedButton.icon(
                            key: const ValueKey('dance-home'),
                            style: actionStyle,
                            onPressed: saving ? null : () => leave(home: true),
                            icon: compactActions
                                ? null
                                : const Icon(Icons.home_outlined),
                            label: Text(
                              c.text('返回首页', 'Home'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                children: [
                  if (scrollHeader) resultHeader(short),
                  if (!short &&
                      !context.qin.highContrast &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * .12).clamp(
                        48.0,
                        110.0,
                      ),
                    ),
                  const SizedBox(height: 12),
                  QinStatus(
                    key: const ValueKey('dance-save-status'),
                    backgroundOpacity: .92,
                    tone: saved
                        ? QinTone.success
                        : saving
                        ? QinTone.neutral
                        : QinTone.error,
                    text: c.text(
                      saved
                          ? '已保存训练记录'
                          : saving
                          ? '正在保存训练记录…'
                          : '保存失败，请重试。',
                      saved
                          ? 'Training record saved'
                          : saving
                          ? 'Saving training record…'
                          : 'Save failed. Please retry.',
                    ),
                    child: saved && date != null
                        ? Text(
                            date,
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : !saved && !saving
                        ? QinFilledButton(
                            onPressed: save,
                            child: Text(c.text('重试保存', 'Retry save')),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  summary(parts),
                  if (saved &&
                      widget.showAssistant &&
                      r['session_id'] is String) ...[
                    const SizedBox(height: 12),
                    CaptureResultCard(
                      c: c,
                      recordId: widget.record['session_id'] as String,
                    ),
                    AssistantReviewCard(
                      c: c,
                      recordId: r['session_id'] as String,
                      title:
                          (r[c.chinese ? 'title_zh' : 'title_en'] ??
                                  r['title'] ??
                                  c.text('舞蹈跟练', 'Dance practice'))
                              as String,
                      date: widget.alreadySaved ? date?.split(' ').first : null,
                    ),
                  ],
                  for (final p in parts) ...[
                    const SizedBox(height: 12),
                    QinPanel(
                      backgroundOpacity: .92,
                      child: Row(
                        children: [
                          Expanded(child: Text(p['title'] as String)),
                          Flexible(
                            child: Text(
                              (p['active_ms'] as int) == 0
                                  ? c.text('未播放', 'Not played')
                                  : durationLabel(p['active_ms'] as int),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
