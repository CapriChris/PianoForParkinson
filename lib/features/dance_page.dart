import 'capture_widgets.dart';
import '../ui/qin_press.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../data/training_schedule_repository.dart';
import '../domain/contracts.dart';
import '../domain/dance_training.dart';
import '../ui/qin_components.dart';
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
  DanceCourse selectedCourse = chineseDanceCourse;
  final captureKey = GlobalKey<CapturePreparationState>();
  late Future<List<Json>> records = scheduleStore(c).dances();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Navigator.canPop(context) ? const QinBackButton() : null,
      title: Text(
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
                                    builder: (context) => AlertDialog(
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
        : QinActionPage(
            actions: [
              QinFilledButton.icon(
                key: const ValueKey('start-dance'),
                onPressed: () async {
                  await c.stopAllPlayback();
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => DancePlayerPage(
                        c: c,
                        course: selectedCourse,
                        capture: captureKey.currentState?.claim(),
                      ),
                    ),
                  );
                  if (mounted && widget.history) {
                    setState(() => records = scheduleStore(c).dances());
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(c.text('开始练习', 'Start practice')),
              ),
            ],
            children: [
              CapturePreparation(key: captureKey, c: c),
              Text(
                c.text('选择课程', 'Choose a course'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final course in danceCourses)
                ListTile(
                  key: ValueKey('dance-course-${course.id}'),
                  selected: selectedCourse.id == course.id,
                  leading: Icon(
                    selectedCourse.id == course.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(course.localizedTitle(c.chinese)),
                  subtitle: Text(
                    c.text(
                      '${course.parts.length} 部分 · ${course.id == chineseDanceCourse.id ? "中文视频" : "英语视频"}',
                      '${course.parts.length} parts · ${course.id == chineseDanceCourse.id ? "Chinese video" : "English video"}',
                    ),
                  ),
                  onTap: () => setState(() => selectedCourse = course),
                ),
              const SizedBox(height: 12),
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
