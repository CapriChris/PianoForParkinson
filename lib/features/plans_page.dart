import '../ui/qin_dialog.dart';
import '../ui/qin_press.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;

import '../ui/qin_theme.dart';

import '../app/app_controller.dart';
import '../domain/contracts.dart';
import '../domain/cognitive_tasks.dart';
import '../domain/dance_training.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../platform/plan_reminders.dart';
import 'dance_page.dart';
import 'reminder_setup_page.dart';

// Visual tuning: logical pixels and opacity values from 0 (clear) to 1 (solid).
const double planHeaderBaseHeight = 144;
const double planCardBackgroundOpacity = .90;
const double planCardImageOpacity = .9;
const Alignment planCardImageAlignment = Alignment.centerRight;
const double planAddButtonSize = 64;
const double planAddButtonBottomGap = 20;
const double planAddButtonOpacity = .84;

class PlansPage extends StatefulWidget {
  const PlansPage({super.key, required this.c, required this.onStart});
  final AppController c;
  final Future<void> Function(String kind) onStart;
  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> with WidgetsBindingObserver {
  AppController get c => widget.c;
  List<Json> items = [];
  final selected = <String>{};
  bool selecting = false, busy = false, loading = true;
  String? error, reminderError;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
  }

  Future<void> reload() async {
    final request = ++generation;
    try {
      final store = scheduleStore(c);
      final today = DateTime.now();
      await store.disableExpiredPlans(today);
      final result = await store.summaries(today);
      if (!mounted || request != generation) return;
      setState(() {
        items = result;
        selected.retainAll(items.map((v) => v['plan']['id'] as String));
        if (selected.isEmpty) selecting = false;
        loading = false;
        error = null;
      });
      try {
        await PlanReminders.instance.sync(store, chinese: c.chinese);
        if (mounted && request == generation) {
          setState(() => reminderError = null);
        }
      } catch (_) {
        if (mounted && request == generation) {
          setState(
            () => reminderError = c.text(
              '提醒暂不可用，计划仍可正常使用。',
              'Reminders unavailable. Plans still work.',
            ),
          );
        }
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = c.text('计划读取失败，请重试', 'Unable to load plans. Please retry.');
        });
      }
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    try {
      await operation();
      busy = false;
      await reload();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(c.text('操作失败，请重试', 'Unable to save. Please retry.')),
          ),
        );
      }
    } finally {
      busy = false;
    }
  }

  Future<void> edit([Json? plan]) async {
    if (busy) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlanEditor(c: c, plan: plan),
      ),
    );
    if (saved == true) await reload();
  }

  void toggleSelection(String id) => setState(() {
    selecting = true;
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });

  Future<void> deleteSelected() async {
    final ids = selected.toList();
    if (ids.isEmpty || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => QinDialog(
        title: Text(
          c.text('删除这 ${ids.length} 项计划？', 'Delete ${ids.length} plans?'),
        ),
        content: Text(
          c.text(
            '训练记录会保留，计划提醒将取消。',
            'Training records will be kept. Plan reminders will be cancelled.',
          ),
        ),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('取消', 'Cancel')),
          ),
          QinFilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.text('删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await run(() => scheduleStore(c).deletePlans(ids));
  }

  String schedule(Json p) {
    final days = Set<int>.from(p['days'] as List);
    final repeat = days.isEmpty
        ? p['start'] as String
        : repeatDaysLabel(days, c);
    final training = p['kind'] == 'dance'
        ? c.text('舞蹈训练', 'Dance training')
        : p['kind'] == 'piece'
        ? c.text('钢琴曲目', 'Piano pieces')
        : p['training_id'] != null
        ? taskTitle(p['training_id'] as String, c.chinese)
        : c.text('钢琴练习', 'Piano exercises');
    return '$training · $repeat';
  }

  Widget planSurface(Json plan, String id, Widget content) {
    final base = selecting && selected.contains(id)
        ? context.qin.soft
        : context.qin.surface;
    final artwork = plan['kind'] == 'dance'
        ? '36-practice-dance.png'
        : plan['kind'] == 'piece'
        ? '13-open-score.png'
        : qinPracticeImage(plan['training_id'] as String? ?? '');
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: context.qin.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: context.qin.highContrast
                    ? 1
                    : planCardBackgroundOpacity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: base),
                    if (!context.qin.highContrast) ...[
                      Opacity(
                        opacity: planCardImageOpacity,
                        child: Image.asset(
                          'assets/ui_images/${artwork.replaceAll('.png', '.webp')}',
                          fit: BoxFit.cover,
                          alignment: planCardImageAlignment,
                          cacheWidth: 600,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              base.withValues(alpha: .98),
                              base.withValues(alpha: .92),
                              base.withValues(alpha: .8),
                              base.withValues(alpha: .72),
                            ],
                            stops: const [0, .4, .75, 1],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }

  Widget planCard(Json item) {
    final p = item['plan'] as Json;
    final id = p['id'] as String;
    final today = DateTime.now();
    final expired = planExpired(p, today);
    final paused = p['paused'] == true || expired;
    final disabledInk = context.qin.highContrast
        ? context.qin.muted
        : context.qin.muted.withValues(alpha: .72);
    final textColor = paused ? disabledInk : null;
    final due = planDue(p, today);
    final minutes = p['target_type'] == 'minutes';
    final progress = item['progress'] as int;
    final target = (p['target'] as int) * (minutes ? 60000 : 1);
    final unit = c.text(minutes ? '分钟' : '次', minutes ? 'min' : 'sessions');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: QinInkWell(
        surfaceBuilder: (surface) => planSurface(p, id, surface),
        key: ValueKey('plan-card-$id'),
        borderRadius: BorderRadius.circular(18),
        onTap: busy
            ? null
            : () {
                selecting ? toggleSelection(id) : edit(p);
              },
        onLongPress: busy ? null : () => toggleSelection(id),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p['title'] as String,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: textColor),
                    ),
                  ),
                  if (selecting)
                    Checkbox(
                      value: selected.contains(id),
                      onChanged: busy ? null : (_) => toggleSelection(id),
                    )
                  else
                    Semantics(
                      label: c.text(
                        '启用计划：${p['title']}',
                        'Enable plan: ${p['title']}',
                      ),
                      child: QinPressBlock(
                        child: Switch(
                          key: ValueKey('plan-enabled-$id'),
                          value: !paused,
                          onChanged: busy || expired
                              ? null
                              : (value) => run(
                                  () =>
                                      scheduleStore(c)
                                          .savePlan({...p, 'paused': !value}),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                schedule(p),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: textColor),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      due
                          ? '${c.text('今日 ', 'Today ')}${minutes ? (progress / 60000).toStringAsFixed(1) : progress} / ${p['target']} $unit'
                          : c.text(
                              expired
                                  ? '已结束'
                                  : paused
                                  ? '已禁用'
                                  : '今日无安排',
                              expired
                                  ? 'Ended'
                                  : paused
                                  ? 'Disabled'
                                  : 'Not scheduled today',
                            ),
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: textColor),
                    ),
                  ),
                  if (!selecting && !paused && !expired) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          onLongPress: () {},
                          child: QinOutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: context.qin.primary),
                              disabledForegroundColor: context.qin.primary,
                              disabledBackgroundColor: context.qin.surface,
                              backgroundColor: context.qin.surface,
                            ),
                            onPressed: busy || (due && progress >= target)
                                ? null
                                : () async {
                                    final trainingId =
                                        p['training_id'] as String?;
                                    await widget.onStart(
                                      trainingId == null || p['kind'] == 'piece'
                                          ? p['kind'] as String
                                          : '${p['kind']}:$trainingId',
                                    );
                                    if (mounted) await reload();
                                  },
                            child: Text(
                              c.text(
                                due && progress >= target ? '已完成' : '开始练习',
                                due && progress >= target
                                    ? 'Completed'
                                    : 'Start practice',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (due) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (progress / target).clamp(0, 1)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget selectionBar() => QinPanel(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: LayoutBuilder(
      builder: (context, size) {
        const gap = 8.0;
        const horizontalPadding = 8.0;
        final style = Theme.of(context).textTheme.bodySmall!;
        double widthOf(String label) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width.ceilToDouble();
          painter.dispose();
          return width;
        }

        final all = selected.length == items.length;
        final selectLabel = c.text('全选', 'Select all');
        final deselectLabel = c.text('全不选', 'Deselect all');
        final countLabel = c.text(
          '已选 ${selected.length} 项',
          '${selected.length} selected',
        );
        final cancelLabel = c.text('取消', 'Cancel'),
            deleteLabel = c.text('删除', 'Delete');
        double buttonWidth(String label) =>
            (widthOf(label) + 2 * horizontalPadding).clamp(
              kMinInteractiveDimension,
              double.infinity,
            );
        final rightWidth =
            buttonWidth(cancelLabel) + buttonWidth(deleteLabel) + gap;
        final sideWidth = [
          rightWidth,
          buttonWidth(selectLabel),
          buttonWidth(deselectLabel),
        ].reduce((a, b) => a > b ? a : b);
        final buttonStyle = TextButton.styleFrom(
          minimumSize: const Size.square(kMinInteractiveDimension),
          padding: const EdgeInsets.symmetric(horizontal: horizontalPadding),
          textStyle: style,
        );
        final selectAll = QinTextButton(
          style: buttonStyle,
          onPressed: busy
              ? null
              : () => setState(() {
                  all
                      ? selected.clear()
                      : selected.addAll(
                          items.map((v) => v['plan']['id'] as String),
                        );
                }),
          child: Text(
            all ? deselectLabel : selectLabel,
            textAlign: TextAlign.center,
          ),
        );
        final count = Text(
          countLabel,
          style: style,
          textAlign: TextAlign.center,
        );
        final actions = Wrap(
          alignment: WrapAlignment.end,
          spacing: gap,
          runSpacing: gap,
          children: [
            QinTextButton(
              style: buttonStyle,
              onPressed: busy
                  ? null
                  : () => setState(() {
                      selecting = false;
                      selected.clear();
                    }),
              child: Text(cancelLabel),
            ),
            QinFilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.square(kMinInteractiveDimension),
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                ),
                textStyle: style,
              ),
              onPressed: busy || selected.isEmpty ? null : deleteSelected,
              child: Text(deleteLabel),
            ),
          ],
        );
        if (size.maxWidth >= 2 * sideWidth + widthOf(countLabel) + 2 * gap) {
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: selectAll,
                ),
              ),
              const SizedBox(width: gap),
              count,
              const SizedBox(width: gap),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actions,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(child: selectAll),
                const SizedBox(width: gap),
                Expanded(child: count),
              ],
            ),
            const SizedBox(height: gap),
            Align(alignment: AlignmentDirectional.centerEnd, child: actions),
          ],
        );
      },
    ),
  );

  Widget emptyPlans() => LayoutBuilder(
    builder: (context, bounds) {
      final bottomSpace =
          planAddButtonSize +
          planAddButtonBottomGap +
          24 +
          MediaQuery.paddingOf(context).bottom;
      return SingleChildScrollView(
        padding: qinPagePadding(context).copyWith(top: 0, bottom: bottomSpace),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (bounds.maxHeight - bottomSpace).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Center(
            child: QinPanel(
              key: const ValueKey('plan-empty-card'),
              soft: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    c.text('暂无计划', 'No plans yet'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    c.text(
                      '点击下方按钮创建你的计划',
                      'Tap the button below to create your plan.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !selecting,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && selecting) {
        setState(() {
          selecting = false;
          selected.clear();
        });
      }
    },
    child: LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final headerHeight =
            (planHeaderBaseHeight + (scale - 1).clamp(0.0, 2.0) * 100).clamp(
              0.0,
              bounds.maxHeight * .4,
            );
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: headerHeight,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.text('训练计划', 'Training plans'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            c.text(
                              '按自己的节奏，\n安排练习。',
                              'Make time for\nthe practice you enjoy.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (selecting)
                  Padding(
                    key: const ValueKey('plan-selection-toolbar'),
                    padding: qinPagePadding(context)
                        .copyWith(top: 0, bottom: 12),
                    child: selectionBar(),
                  ),
                Expanded(
                  child: !loading && error == null && items.isEmpty
                      ? emptyPlans()
                      : QinPageList(
                          padding: qinPagePadding(context).copyWith(
                            bottom: selecting
                                ? 24
                                : planAddButtonSize +
                                      planAddButtonBottomGap +
                                      24,
                          ),
                          children: [
                            if (error != null)
                              QinStatus(
                                tone: QinTone.error,
                                text: error!,
                                child: QinTextButton(
                                  onPressed: reload,
                                  child: Text(c.text('重试', 'Retry')),
                                ),
                              ),
                            if (reminderError != null &&
                                items.any(
                                  (v) =>
                                      v['plan']['reminder'] == true &&
                                      v['plan']['paused'] != true,
                                )) ...[
                              QinStatus(
                                tone: QinTone.warning,
                                text: reminderError!,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (reminderError == null &&
                                items.any(
                                  (v) =>
                                      v['plan']['reminder'] == true &&
                                      v['plan']['paused'] != true,
                                ))
                              PlanReminderSetupHint(c: c),
                            if (loading)
                              const Center(child: CircularProgressIndicator()),
                            for (final item in items) planCard(item),
                          ],
                        ),
                ),
              ],
            ),
            if (!selecting)
              Positioned(
                left: 0,
                right: 0,
                bottom:
                    planAddButtonBottomGap +
                    MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: QinIconButton(
                    key: const ValueKey('create-plan-floating'),
                    tooltip: c.text('新建计划', 'New plan'),
                    onPressed: busy ? null : () => edit(),
                    style: ButtonStyle(
                      fixedSize: const WidgetStatePropertyAll(
                        Size.square(planAddButtonSize),
                      ),
                      shape: const WidgetStatePropertyAll(CircleBorder()),
                      backgroundColor: WidgetStatePropertyAll(
                        context.qin.primary.withValues(
                          alpha: context.qin.highContrast
                              ? 1
                              : planAddButtonOpacity,
                        ),
                      ),
                      foregroundColor: WidgetStatePropertyAll(
                        context.qin.onPrimary,
                      ),
                      iconSize: const WidgetStatePropertyAll(32),
                      elevation: const WidgetStatePropertyAll(4),
                      shadowColor: WidgetStatePropertyAll(
                        Colors.black.withValues(alpha: .15),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.c, this.plan});
  final AppController c;
  final Json? plan;
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  static const _fieldLabelWidth = 100.0;
  static const _fieldGap = 8.0;
  static const _stepButtonWidth = kMinInteractiveDimension;
  static const _stepLineWidth = 1.0;
  static const _targetPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 14,
  );
  static const _maxTarget = 1000;

  AppController get c => widget.c;
  late final title = TextEditingController(
    text: widget.plan?['title'] as String? ?? '',
  );
  late final target = TextEditingController(
    text: '${widget.plan?['target'] ?? 1}',
  );
  late String kind = widget.plan?['kind'] as String? ?? 'dance';
  late String? trainingId = kind == 'piece'
      ? 'any'
      : widget.plan?['training_id'] as String?;
  late DateTime start = DateTime.parse(
    widget.plan?['start'] as String? ?? localDay(DateTime.now()),
  );
  late DateTime? end = widget.plan?['end'] == null
      ? null
      : DateTime.parse(widget.plan!['end'] as String);
  late Set<int> days = Set<int>.from(widget.plan?['days'] as List? ?? []);
  late bool reminder = widget.plan?['reminder'] as bool? ?? true;
  late String repeatMode =
      widget.plan?['repeat_mode'] as String? ?? repeatModeFor(days);
  late final hourController = FixedExtentScrollController(
    initialItem: time.hour,
  );
  late final minuteController = FixedExtentScrollController(
    initialItem: time.minute,
  );
  late final defaultTime = TimeOfDay.now();
  late TimeOfDay time = TimeOfDay(
    hour: widget.plan?['hour'] as int? ?? defaultTime.hour,
    minute: widget.plan?['minute'] as int? ?? defaultTime.minute,
  );
  late final String planId = widget.plan?['id'] as String? ?? uuid();
  bool saving = false, allowLeave = false, leaveDialog = false;
  String? error;
  late final String initialValues;
  String get values => canonical({
    'title': title.text,
    'target': target.text,
    'kind': kind,
    'training': trainingId,
    'start': localDay(start),
    'end': end == null ? null : localDay(end!),
    'days': days.toList()..sort(),
    'mode': repeatMode,
    'reminder': reminder,
    'hour': time.hour,
    'minute': time.minute,
  });
  bool get dirty => values != initialValues;
  @override
  void initState() {
    super.initState();
    initialValues = values;
    title.addListener(changed);
    target.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> closeEditor([bool? result]) async {
    setState(() => allowLeave = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> requestLeave() async {
    if (saving || leaveDialog) return;
    if (!dirty) {
      await closeEditor();
      return;
    }
    leaveDialog = true;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => QinDialog(
        title: Text(c.text('是否保存更改？', 'Save changes?')),
        actions: [
          QinTextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(c.text('放弃', 'Discard')),
          ),
          QinFilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(c.text('保存', 'Save')),
          ),
        ],
      ),
    );
    leaveDialog = false;
    if (!mounted) return;
    if (choice == true) {
      await save();
    } else if (choice == false) {
      await closeEditor(false);
    }
  }

  OutlineInputBorder get inputBorder => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: context.qin.edge),
  );
  @override
  void dispose() {
    title.dispose();
    target.dispose();
    hourController.dispose();
    minuteController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final count = int.tryParse(target.text);
    if (title.text.trim().isEmpty ||
        count == null ||
        count < 1 ||
        count > _maxTarget ||
        (end != null && end!.isBefore(start)) ||
        (kind == 'exercise' && trainingId == null)) {
      setState(
        () => error = c.text(
          '请填写名称、1–$_maxTarget次目标、有效日期，并选择练习内容。',
          'Enter a name, 1–$_maxTarget sessions, valid dates and a training activity.',
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      if (reminder && !await PlanReminders.instance.request()) {
        if (mounted) {
          setState(() {
            reminder = false;
            error = c.text(
              '通知权限未开启，已关闭提醒。再次点完成可保存计划。',
              'Notifications are off. Tap Done again to save without reminders.',
            );
          });
        }
        return;
      }
      await scheduleStore(c).savePlan({
        'id': planId,
        'version': 1,
        'title': title.text.trim(),
        'kind': kind,
        'start': localDay(start),
        'end': end == null ? null : localDay(end!),
        'days': days.toList()..sort(),
        'target_type': 'count',
        if (kind == 'exercise') 'training_id': trainingId,
        'repeat_mode': repeatMode,
        'target': count,
        'reminder': reminder,
        'hour': time.hour,
        'minute': time.minute,
        'paused': widget.plan?['paused'] == true,
      });
      if (reminder || widget.plan?['reminder'] == true) {
        await PlanReminders.instance.sync(scheduleStore(c), chinese: c.chinese);
      }
      if (mounted) await closeEditor(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text('保存失败，请重试', 'Save failed. Please retry.'),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> chooseTraining() async {
    final chosen = await Navigator.push<(String, String)>(
      context,
      MaterialPageRoute(
        builder: (_) => PlanTrainingPicker(
          c: c,
          selectedKind: kind,
          selectedId: trainingId,
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        kind = chosen.$1;
        trainingId = chosen.$2;
      });
    }
  }

  String get trainingTitle {
    if (trainingId == null) return c.text('请选择', 'Choose activity');
    if (kind == 'piece') {
      return c.text('钢琴曲目', 'Piano pieces');
    }
    return taskTitle(trainingId!, c.chinese);
  }

  Widget fieldRow(String label, Widget field, {double? minimumFieldWidth}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, size) {
            if (minimumFieldWidth != null &&
                size.maxWidth <
                    _fieldLabelWidth + _fieldGap + minimumFieldWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label),
                  const SizedBox(height: _fieldGap),
                  field,
                ],
              );
            }
            return Row(
              children: [
                SizedBox(width: _fieldLabelWidth, child: Text(label)),
                const SizedBox(width: _fieldGap),
                Expanded(child: field),
              ],
            );
          },
        ),
      );

  Widget group(List<Widget> children) => QinPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  void adjustTarget(int delta) {
    final value = ((int.tryParse(target.text) ?? 0) + delta)
        .clamp(1, _maxTarget)
        .toString();
    target.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Widget targetStepper(String unit) {
    final count = int.tryParse(target.text);
    const buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.zero),
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.qin.surface,
              border: Border.all(
                color: context.qin.edge,
                width: _stepLineWidth,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _stepButtonWidth,
                    child: QinIconButton(
                      key: const ValueKey('plan-target-decrease'),
                      style: buttonStyle,
                      tooltip: c.text('减少1次', 'Decrease by one'),
                      onPressed: saving || (count ?? 1) <= 1
                          ? null
                          : () => adjustTarget(-1),
                      icon: const Icon(Icons.remove),
                    ),
                  ),
                  VerticalDivider(
                    width: _stepLineWidth,
                    thickness: _stepLineWidth,
                    color: context.qin.line,
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('plan-target-input'),
                      controller: target,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: _targetPadding,
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: _stepLineWidth,
                    thickness: _stepLineWidth,
                    color: context.qin.line,
                  ),
                  SizedBox(
                    width: _stepButtonWidth,
                    child: QinIconButton(
                      key: const ValueKey('plan-target-increase'),
                      style: buttonStyle,
                      tooltip: c.text('增加1次', 'Increase by one'),
                      onPressed: saving || (count ?? 0) >= _maxTarget
                          ? null
                          : () => adjustTarget(1),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: _fieldGap),
        Tooltip(message: c.text('次', 'sessions'), child: Text(unit)),
      ],
    );
  }

  Widget targetRow() => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final inputStyle = theme.useMaterial3
          ? theme.textTheme.bodyLarge
          : theme.textTheme.titleMedium;
      final unitStyle = DefaultTextStyle.of(context).style;
      final unit = c.text('次', '×');
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      );
      double widthOf(String text, TextStyle? style) {
        painter.text = TextSpan(text: text, style: style);
        painter.layout();
        return painter.width.ceilToDouble();
      }

      final fieldWidth =
          2 * _stepButtonWidth +
          4 * _stepLineWidth + // Two dividers and both sides of the border.
          _targetPadding.horizontal +
          widthOf('$_maxTarget', inputStyle) +
          _fieldGap +
          widthOf(unit, unitStyle);
      painter.dispose();
      return fieldRow(
        c.text('目标', 'Target'),
        targetStepper(unit),
        minimumFieldWidth: fieldWidth,
      );
    },
  );

  Widget get timePicker {
    final extent = MediaQuery.textScalerOf(context).scale(24) * 1.6;
    Widget wheel(bool hour) => SizedBox(
      width: MediaQuery.textScalerOf(context).scale(28) * 2.5,
      child: CupertinoPicker(
        key: ValueKey(hour ? 'plan-hour-picker' : 'plan-minute-picker'),
        scrollController: hour ? hourController : minuteController,
        itemExtent: extent,
        looping: true,
        selectionOverlay: DecoratedBox(
          decoration: BoxDecoration(
            color: context.qin.soft.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onSelectedItemChanged: (value) {
          HapticFeedback.selectionClick();
          setState(
            () => time = TimeOfDay(
              hour: hour ? value : time.hour,
              minute: hour ? time.minute : value,
            ),
          );
        },
        children: [
          for (var i = 0; i < (hour ? 24 : 60); i++)
            Center(
              child: Text(
                i.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
        ],
      ),
    );
    return Center(
      child: SizedBox(
        height: extent * 5,
        width: (MediaQuery.textScalerOf(context).scale(28) * 7.5).clamp(
          240.0,
          double.infinity,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: (MediaQuery.textScalerOf(context).scale(28) * 7.5).clamp(
              240.0,
              double.infinity,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                wheel(true),
                Text(c.text('时', 'h')),
                const SizedBox(width: 24),
                wheel(false),
                Text(c.text('分', 'm')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowLeave || (!dirty && !saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) requestLeave();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: QinIconButton(
          tooltip: c.text('返回', 'Back'),
          onPressed: saving ? null : requestLeave,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          QinTextButton(
            onPressed: saving ? null : save,
            child: Text(
              c.text(saving ? '保存中…' : '完成', saving ? 'Saving…' : 'Done'),
            ),
          ),
        ],
        title: Text(
          c.text(
            widget.plan == null ? '新建计划' : '编辑计划',
            widget.plan == null ? 'New plan' : 'Edit plan',
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: QinPageList(
          children: [
            if (error != null) ...[
              QinStatus(tone: QinTone.warning, text: error!),
              const SizedBox(height: 12),
            ],
            group([
              fieldRow(
                c.text('计划名称', 'Plan name'),
                TextField(
                  controller: title,
                  maxLength: 60,
                  decoration: InputDecoration(
                    hintText: c.text('为计划取个名字', 'Name your plan'),
                    counterText: '',
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    suffixIcon: QinIconButton(
                      tooltip: c.text('清空名称', 'Clear name'),
                      onPressed: title.clear,
                      icon: const Icon(Icons.cancel_outlined),
                    ),
                  ),
                ),
              ),
              fieldRow(
                c.text('计划类型', 'Training'),
                QinOutlinedButton(
                  onPressed: () async {
                    final value = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: context.qin.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      builder: (context) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final type in ['dance', 'piano'])
                                QinListTile(
                                  title: Text(
                                    c.text(
                                      type == 'dance' ? '舞蹈训练' : '钢琴训练',
                                      type == 'dance'
                                          ? 'Dance training'
                                          : 'Piano training',
                                    ),
                                  ),
                                  trailing: Icon(
                                    (kind == 'dance') == (type == 'dance')
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: context.qin.primary,
                                  ),
                                  onTap: () => Navigator.pop(context, type),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (value != null &&
                        mounted &&
                        ((kind == 'dance') != (value == 'dance'))) {
                      setState(() {
                        kind = value == 'dance' ? 'dance' : 'exercise';
                        trainingId = null;
                      });
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.text(
                            kind == 'dance' ? '舞蹈训练' : '钢琴训练',
                            kind == 'dance'
                                ? 'Dance training'
                                : 'Piano training',
                          ),
                        ),
                      ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                ),
              ),
              if (kind != 'dance')
                fieldRow(
                  c.text('练习内容', 'Activity'),
                  QinOutlinedButton(
                    onPressed: chooseTraining,
                    child: Row(
                      children: [
                        Expanded(child: Text(trainingTitle)),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              targetRow(),
            ]),
            const SizedBox(height: 16),
            group([
              fieldRow(
                c.text('开始日期', 'Start date'),
                QinOutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) {
                      setState(() {
                        start = d;
                        if (end != null && end!.isBefore(d)) end = null;
                      });
                    }
                  },
                  child: Row(
                    children: [
                      Expanded(child: Text(localDay(start))),
                      const Icon(Icons.calendar_month_outlined),
                    ],
                  ),
                ),
              ),
              fieldRow(
                c.text('结束日期', 'End date'),
                QinOutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: end ?? start,
                      firstDate: start,
                      lastDate: DateTime(2100),
                    );
                    if (d != null && mounted) setState(() => end = d);
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          end == null ? c.text('不限', 'No end') : localDay(end!),
                        ),
                      ),
                      const Icon(Icons.calendar_month_outlined),
                    ],
                  ),
                ),
              ),
              if (end != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: QinTextButton(
                    onPressed: () => setState(() => end = null),
                    child: Text(c.text('清除结束日期', 'Clear end date')),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            QinListTile(
              surfaceBuilder: (surface) => Card(child: surface),
              key: const ValueKey('plan-repeat'),
              title: Text(c.text('重复', 'Repeat')),
              subtitle: MediaQuery.textScalerOf(context).scale(1) > 1.4
                  ? Text(repeatLabel(repeatMode, days, c))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (MediaQuery.textScalerOf(context).scale(1) <= 1.4)
                    Text(repeatLabel(repeatMode, days, c)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () async {
                final result = await Navigator.push<(String, Set<int>)>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PlanRepeatPage(c: c, mode: repeatMode, days: days),
                  ),
                );
                if (result != null && mounted) {
                  setState(() {
                    repeatMode = result.$1;
                    days = result.$2;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            group([
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.text('通知提醒', 'Notifications')),
                value: reminder,
                onChanged: (value) => setState(() => reminder = value),
              ),
              if (reminder) ...[timePicker, PlanReminderSetupHint(c: c)],
            ]),
          ],
        ),
      ),
    ),
  );
}

class PlanReminderSetupHint extends StatefulWidget {
  const PlanReminderSetupHint({super.key, required this.c, this.reminders});
  static const hiddenPreferenceKey = 'reminder_setup_hint_hidden_v1';
  final AppController c;
  final PlanReminders? reminders;
  @override
  State<PlanReminderSetupHint> createState() => _PlanReminderSetupHintState();
}

class _PlanReminderSetupHintState extends State<PlanReminderSetupHint>
    with WidgetsBindingObserver {
  PlanReminderAccess? access;
  bool busy = false;
  bool hiddenThisTime = false;
  String? error;
  AppController get c => widget.c;
  PlanReminders get reminders => widget.reminders ?? PlanReminders.instance;
  bool get permanentlyHidden =>
      c.settings[PlanReminderSetupHint.hiddenPreferenceKey] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(preferencesChanged);
    if (!permanentlyHidden) refresh();
  }

  void preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PlanReminderSetupHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.c != c) {
      oldWidget.c.removeListener(preferencesChanged);
      c.addListener(preferencesChanged);
      hiddenThisTime = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(preferencesChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final result = await reminders.access();
      if (mounted) {
        setState(() {
          access = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '无法读取提醒权限，请重试。',
            'Unable to check reminder permissions. Retry.',
          ),
        );
      }
    }
  }

  Future<void> configure() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReminderSetupPage(chinese: c.chinese),
        ),
      );
      if (!mounted) return;
      await reminders.sync(scheduleStore(c), chinese: c.chinese);
      await refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '提醒设置失败，请重试。',
            'Unable to set up reminders. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hiddenThisTime || permanentlyHidden) return const SizedBox.shrink();
    if (error == null && access == null) {
      return const SizedBox.shrink();
    }
    final message =
        error ??
        switch (access!) {
          PlanReminderAccess.inexact => c.text(
            '准时提醒未开启，通知可能延迟。请允许“闹钟和提醒”。',
            'Reminders may arrive late. Allow alarms and reminders for accurate timing.',
          ),
          PlanReminderAccess.notificationsOff => c.text(
            '通知权限未开启，无法收到训练提醒。',
            'Notifications are off. Enable them to receive training reminders.',
          ),
          PlanReminderAccess.channelQuiet => c.text(
            '训练提醒可能以静默方式显示，可在设置引导中检查通知显示。',
            'Training reminders may be quiet. Check notification display in the setup guide.',
          ),
          PlanReminderAccess.ready => c.text(
            '通知与准时提醒已开启。请进入提醒设置，检查自启动和后台活动。',
            'Notifications and accurate reminders are enabled. Open Reminder setup to check auto-start and background activity.',
          ),
        };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: QinPanel(
        soft: error == null && access == PlanReminderAccess.ready,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(Icons.info_outline),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message),
                  ),
                ),
                QinIconButton(
                  key: const ValueKey('reminder-hint-close'),
                  tooltip: c.text('关闭提醒设置提示', 'Dismiss reminder setup tip'),
                  onPressed: busy ? null : dismissHint,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            QinOutlinedButton(
              onPressed: busy ? null : configure,
              child: Text(c.text('提醒设置', 'Reminder setup')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> dismissHint() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final permanent = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => QinDialog(
          content: Text(
            c.text(
              '请确保已开启所需权限后再选择“不再提醒”',
              'Make sure the required permissions are enabled before choosing Don’t show again.',
            ),
          ),
          actions: [
            QinOutlinedButton(
              key: const ValueKey('reminder-hint-never'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffb3261e),
                side: const BorderSide(color: Color(0xffb3261e)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(c.text('不再提醒', 'Don’t show again')),
            ),
            QinOutlinedButton(
              key: const ValueKey('reminder-hint-once'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(c.text('本次关闭', 'Dismiss this time')),
            ),
          ],
        ),
      );
      if (permanent == null || !mounted) return;
      if (permanent) {
        await c.updateSettings(
          values: {PlanReminderSetupHint.hiddenPreferenceKey: true},
        );
      } else {
        setState(() => hiddenThisTime = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.text(
                '未能保存提示设置，请重试。',
                'Could not save this preference. Please retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

String repeatModeFor(Set<int> days) {
  if (days.isEmpty) return 'once';
  if (days.length == 7) return 'daily';
  if (days.length == 5 && days.containsAll([1, 2, 3, 4, 5])) return 'weekdays';
  if (days.length == 2 && days.containsAll([6, 7])) return 'weekends';
  return 'custom';
}

String repeatLabel(String mode, Set<int> days, AppController c) =>
    switch (mode) {
      'once' => c.text('仅一次', 'Once'),
      'daily' => c.text('每天', 'Every day'),
      'weekdays' => c.text('工作日', 'Weekdays'),
      'weekends' => c.text('周末', 'Weekends'),
      _ => c.text('自定义', 'Custom'),
    };

class PlanRepeatPage extends StatefulWidget {
  const PlanRepeatPage({
    super.key,
    required this.c,
    required this.mode,
    required this.days,
  });
  final AppController c;
  final String mode;
  final Set<int> days;
  @override
  State<PlanRepeatPage> createState() => _PlanRepeatPageState();
}

class _PlanRepeatPageState extends State<PlanRepeatPage> {
  late String mode = widget.mode;
  late Set<int> custom = {...widget.days};
  Set<int> get days => switch (mode) {
    'once' => {},
    'daily' => {1, 2, 3, 4, 5, 6, 7},
    'weekdays' => {1, 2, 3, 4, 5},
    'weekends' => {6, 7},
    _ => custom,
  };
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final dayLabels = c.chinese
        ? const ['一', '二', '三', '四', '五', '六', '日']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const QinBackButton() : null,
        title: Text(c.text('重复', 'Repeat')),
        actions: [
          QinTextButton(
            onPressed: mode == 'custom' && custom.isEmpty
                ? null
                : () =>
                      Navigator.pop(context, (repeatModeFor(days), {...days})),
            child: Text(c.text('完成', 'Done')),
          ),
        ],
      ),
      body: QinPageList(
        children: [
          QinPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final value in [
                  'once',
                  'daily',
                  'weekdays',
                  'weekends',
                  'custom',
                ])
                  QinListTile(
                    key: ValueKey('repeat-$value'),
                    title: Text(repeatLabel(value, {}, c)),
                    trailing: Icon(
                      mode == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: context.qin.primary,
                    ),
                    onTap: () => setState(() => mode = value),
                  ),
              ],
            ),
          ),
          if (mode == 'custom') ...[
            const SizedBox(height: 16),
            QinPanel(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Row(
                spacing: 4,
                children: [
                  for (var d = 1; d <= 7; d++)
                    Expanded(
                      child: FilterChip(
                        key: ValueKey('repeat-day-$d'),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        label: SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(dayLabels[d - 1]),
                          ),
                        ),
                        selected: custom.contains(d),
                        onSelected: (value) => setState(() {
                          value ? custom.add(d) : custom.remove(d);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PlanTrainingPicker extends StatelessWidget {
  const PlanTrainingPicker({
    super.key,
    required this.c,
    required this.selectedKind,
    required this.selectedId,
  });
  final AppController c;
  final String selectedKind;
  final String? selectedId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Navigator.canPop(context) ? const QinBackButton() : null,
      title: Text(c.text('练习内容', 'Training activity')),
    ),
    body: QinPageList(
      children: [
        Text(
          c.text('钢琴练习', 'Piano exercises'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final id in exerciseIds)
          QinListTile(
            surfaceBuilder: (surface) => Card(child: surface),
            title: Text(taskTitle(id, c.chinese)),
            trailing: Icon(
              selectedKind == 'exercise' && selectedId == id
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            onTap: () => Navigator.pop(context, ('exercise', id)),
          ),
        const SizedBox(height: 16),
        QinListTile(
          surfaceBuilder: (surface) => Card(child: surface),
          title: Text(c.text('钢琴曲目', 'Piano pieces')),
          trailing: Icon(
            selectedKind == 'piece'
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
          ),
          onTap: () => Navigator.pop(context, ('piece', 'any')),
        ),
      ],
    ),
  );
}

String repeatDaysLabel(Set<int> selected, AppController c) {
  final days = selected.toList()..sort();
  if (days.isEmpty) return c.text('仅一次', 'Once');
  if (days.length == 7) return c.text('每天', 'Every day');
  String name(int day) => c.chinese
      ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day - 1]
      : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day - 1];
  if (days.length > 1 && days.last - days.first == days.length - 1) {
    return '${name(days.first)}${c.text('到', '–')}${name(days.last)}';
  }
  return days.map(name).join('、');
}
