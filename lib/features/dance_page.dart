import '../ui/qin_dialog.dart';
import 'capture_widgets.dart';
import '../ui/qin_press.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/page_title.dart';
import '../app/piano_app.dart' show PracticeCard;
import '../data/training_schedule_repository.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../ui/qin_theme.dart';
import 'dance_player_page.dart';
export 'dance_player_page.dart' show DancePlayerPage;

TrainingScheduleRepository scheduleStore(AppController c) =>
    TrainingScheduleRepository(
      c.repository.db,
      c.repository.profile['profile_id'] as String,
      onPlanChanged: c.cloudSync.trigger,
    );

class DancePage extends StatefulWidget {
  const DancePage({super.key, required this.c, this.history = false});
  final AppController c;
  final bool history;
  @override
  State<DancePage> createState() => _DancePageState();
}

class _DancePageState extends State<DancePage> {
  AppController get c => widget.c;
  bool openingCourse = false;

  Future<void> chooseCourse(DanceCourse course) async {
    if (openingCourse) return;
    setState(() => openingCourse = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DancePreparationPage(c: c, course: course),
        ),
      );
    } finally {
      if (mounted) setState(() => openingCourse = false);
    }
  }

  late Future<List<Json>> records = scheduleStore(c).dances();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Navigator.canPop(context) ? const QinBackButton() : null,
      title: PageTitle(
        c.text(
          widget.history ? '舞蹈记录' : '舞蹈跟练',
          widget.history ? 'Dance history' : 'Dance practice',
        ),
      ),
    ),
    body: widget.history
        ? FutureBuilder<List<Json>>(
            future: records,
            builder: (context, s) {
              if (s.hasError) {
                return Center(
                  child: Text(
                    c.text(
                      '记录暂不可用，请返回重试',
                      'Records unavailable. Please retry.',
                    ),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return QinPageList(
                children: [
                  if (s.data!.isEmpty)
                    Text(c.text('还没有舞蹈记录', 'No dance sessions yet')),
                  for (final r in s.data!)
                    QinPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (r[c.chinese ? 'title_zh' : 'title_en'] ??
                                          r['title'] ??
                                          danceTitle)
                                      as String,
                                ),
                              ),
                              QinIconButton(
                                tooltip: c.text('删除记录', 'Delete record'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => QinDialog(
                                      title: Text(
                                        c.text(
                                          '删除这条舞蹈记录？',
                                          'Delete this dance record?',
                                        ),
                                      ),
                                      content: Text(
                                        c.text(
                                          '相关计划进度将重新计算。',
                                          'Linked plan progress will be recalculated.',
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
                                  if (confirm != true) return;
                                  try {
                                    await scheduleStore(c)
                                        .deleteDance(r['session_id'] as String);
                                    await c.refreshHistory();
                                    if (mounted) {
                                      setState(
                                        () =>
                                            records = scheduleStore(c).dances(),
                                      );
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            c.text(
                                              '删除失败，请重试',
                                              'Unable to delete. Please retry.',
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                          Text(
                            DateTime.fromMillisecondsSinceEpoch(
                              r['started_utc_ms'] as int,
                            ).toLocal().toString().substring(0, 16),
                          ),
                          Text(
                            c.text(
                              '播放 ${(r['active_ms'] / 60000).toStringAsFixed(1)} 分钟 · ${r['confirmed'] == true ? '已确认跟练' : '播放记录'}',
                              'Playback ${(r['active_ms'] / 60000).toStringAsFixed(1)} min · ${r['confirmed'] == true ? 'Practice confirmed' : 'Playback record'}',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          )
        : QinPageList(
            children: [
              QinSectionTitle(
                c.text('选一门喜欢的课程', 'Choose a course you like'),
                subtitle: c.text(
                  '跟随视频，按自己的节奏练习。',
                  'Follow the video and practice at your own pace.',
                ),
              ),
              for (final course in danceCourses) ...[
                PracticeCard(
                  key: ValueKey('dance-course-${course.id}'),
                  icon: Icons.music_video_outlined,
                  artwork: _danceCourseArtwork(course),
                  title: course.localizedTitle(c.chinese),
                  subtitle: _danceCourseLanguage(c, course),
                  onTap: openingCourse ? null : () => chooseCourse(course),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
  );
}

String _danceCourseArtwork(DanceCourse course) =>
    qinDanceCourseImage(course.id) ?? '37-balance-six-course.png';

String _danceCourseLanguage(AppController c, DanceCourse course) =>
    course.id == chineseDanceCourse.id
    ? c.text('中文', 'Chinese')
    : c.text('英文', 'English');

/// Capture consent belongs to the selected practice, after browsing the catalog.
class DancePreparationPage extends StatefulWidget {
  const DancePreparationPage({
    super.key,
    required this.c,
    required this.course,
  });
  final AppController c;
  final DanceCourse course;
  @override
  State<DancePreparationPage> createState() => _DancePreparationPageState();
}

class _DancePreparationPageState extends State<DancePreparationPage> {
  final captureKey = GlobalKey<CapturePreparationState>();
  bool starting = false;
  AppController get c => widget.c;

  Future<void> start() async {
    if (starting || captureKey.currentState?.busy == true) return;
    setState(() => starting = true);
    try {
      await c.stopAllPlayback();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => DancePlayerPage(
            c: c,
            course: widget.course,
            capture: captureKey.currentState?.claim(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const QinBackButton(),
      title: PageTitle(widget.course.localizedTitle(c.chinese)),
    ),
    body: QinActionPage(
      actions: [
        QinFilledButton.icon(
          key: const ValueKey('start-dance'),
          onPressed: starting ? null : start,
          icon: const Icon(Icons.play_arrow),
          label: Text(c.text('开始练习', 'Start practice')),
        ),
      ],
      children: [
        if (!context.qin.highContrast)
          QinPreparationArtwork(
            artworkKey: const ValueKey('dance-preparation-artwork'),
            asset: _danceCourseArtwork(widget.course),
            alignment: Alignment.topCenter,
          ),
        CapturePreparation(key: captureKey, c: c),
        const SizedBox(height: 16),
        QinStatus(
          text: c.text(
            '请留出活动空间，按自己舒服的幅度练习。随时可以暂停，身体不适时停止。',
            'Keep space to move and practice at a comfortable pace. Pause anytime; stop if you feel discomfort.',
          ),
        ),
      ],
    ),
  );
}
