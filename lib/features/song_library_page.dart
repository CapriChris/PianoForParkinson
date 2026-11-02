import '../ui/qin_press.dart';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../ui/qin_components.dart';
import '../ui/qin_music_art.dart';
import '../app/page_title.dart';
import '../app/piano_app.dart';
import '../domain/contracts.dart';

class SongLibraryPage extends StatefulWidget {
  const SongLibraryPage({super.key, required this.c, required this.taskId});
  final AppController c;
  final String taskId;
  @override
  State<SongLibraryPage> createState() => _SongLibraryPageState();
}

class _SongLibraryPageState extends State<SongLibraryPage> {
  bool selecting = false;
  String? error;
  Future<void> choose(Json song) async {
    if (selecting) return;
    setState(() => selecting = true);
    try {
      await widget.c.selectSong(song['content_id'] as String);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InstructionPage(c: widget.c, taskId: widget.taskId),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = widget.c.text(
            '暂时无法选择，请重试。',
            'Unable to select this melody. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final songs = c.content.songsFor(widget.taskId);
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const QinBackButton() : null,
        title: PageTitle(c.text('选择旋律', 'Choose a melody')),
      ),
      body: QinPageList(
        children: [
          QinSectionTitle(
            c.text('选一段喜欢的旋律', 'Choose a melody you like'),
            subtitle: c.text(
              '先听示范，再跟随提示弹奏。',
              'Listen to the demo, then follow the prompts.',
            ),
          ),
          if (error != null) ...[
            QinStatus(text: error!, tone: QinTone.error),
            const SizedBox(height: 16),
          ],
          for (final song in songs) ...[
            PracticeCard(
              icon: Icons.music_note_outlined,
              artwork:
                  qinSongImage(widget.taskId, song['content_id'] as String) ??
                  qinPracticeImage(widget.taskId),
              title: song['localized_title'][c.locale] as String,
              onTap: selecting ? null : () => choose(song),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
