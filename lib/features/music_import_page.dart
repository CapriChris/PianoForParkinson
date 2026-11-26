import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/imported_piece.dart';
import '../domain/piano_piece.dart';
import '../ui/qin_components.dart';
import '../ui/qin_dialog.dart';
import '../ui/qin_press.dart';
import 'piece_sheet_preview.dart';

class MusicImportPage extends StatefulWidget {
  const MusicImportPage({super.key, required this.c});
  final AppController c;
  @override
  State<MusicImportPage> createState() => _MusicImportPageState();
}

class _MusicImportPageState extends State<MusicImportPage> {
  static const channel = MethodChannel('piano_training/music_import/v1');
  final title = TextEditingController(), tempo = TextEditingController();
  final previewKey = GlobalKey<PieceSheetPreviewState>();
  ImportedPieceDraft? draft;
  PianoPiece? preview, complete;
  bool busy = false, saving = false;
  String? error;
  AppController get c => widget.c;

  @override
  void dispose() {
    unawaited(
      channel.invokeMethod<void>('cancelImport').catchError((Object _) {}),
    );
    title.dispose();
    tempo.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.stopAllPlayback();
      final result = await channel.invokeMapMethod<String, dynamic>('pickMp3');
      if (!mounted || result == null) return;
      draft = ImportedPieceDraft(Map<String, dynamic>.from(result));
      title.text = draft!.title;
      tempo.text = '${draft!.tempo}';
      rebuildDraft();
    } on PlatformException catch (failure) {
      if (mounted) {
        setState(
          () => error = switch (failure.code) {
            'E_IMPORT_TOO_LONG' => c.text(
              '请选择 10 分钟以内的 MP3。',
              'Choose an MP3 up to 10 minutes.',
            ),
            'E_IMPORT_TOO_LARGE' => c.text(
              '请选择 100 MiB 以内的 MP3。',
              'Choose an MP3 up to 100 MiB.',
            ),
            'E_IMPORT_NO_MELODY' => c.text(
              '未识别出稳定旋律，请尝试主旋律更清晰的歌曲。',
              'No stable melody found. Try clearer melodic audio.',
            ),
            'E_IMPORT_NOT_MP3' => c.text(
              '这个文件不是可解码的 MP3。',
              'This file is not a decodable MP3.',
            ),
            _ => c.text(
              '导入失败，请重试或更换 MP3 文件。',
              'Import failed. Retry or choose another MP3.',
            ),
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = c.text(
            '无法创建曲目，请重试。',
            'Unable to create this piece. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void rebuildDraft() {
    final value = draft;
    if (value == null) return;
    setState(() {
      try {
        value.title = title.text;
        value.tempo = int.tryParse(tempo.text) ?? 0;
        complete = value.build();
        preview = value.preview();
        error = null;
      } catch (_) {
        complete = preview = null;
        error = c.text(
          '请填写名称、30–240 BPM 原速，并检查音符。最多支持 4096 个音符与休止事件。',
          'Enter a title and an original tempo of 30–240 BPM. Check the notes. Up to 4096 note/rest events are supported.',
        );
      }
    });
  }

  Future<void> edit(int? index) async {
    await previewKey.currentState?.stop();
    if (!mounted) return;
    final note = index == null
        ? <String, dynamic>{'midi': 60, 'start_ms': 0, 'end_ms': 250}
        : draft!.notes[index];
    final midi = TextEditingController(text: '${note['midi']}');
    final start = TextEditingController(text: '${note['start_ms']}');
    final end = TextEditingController(text: '${note['end_ms']}');
    String? validation;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => QinDialog(
          title: Text(c.text('校对音符', 'Edit note')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: midi,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: c.text('音高 MIDI（36–96）', 'MIDI pitch (36–96)'),
                  ),
                ),
                TextField(
                  controller: start,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: c.text('起始时间（毫秒）', 'Start (ms)'),
                  ),
                ),
                TextField(
                  controller: end,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: c.text('结束时间（毫秒）', 'End (ms)'),
                  ),
                ),
                if (validation != null) Text(validation!),
              ],
            ),
          ),
          actions: [
            QinTextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(c.text('取消', 'Cancel')),
            ),
            QinFilledButton(
              onPressed: () {
                final p = int.tryParse(midi.text),
                    a = int.tryParse(start.text),
                    b = int.tryParse(end.text);
                final overlaps =
                    a != null &&
                    b != null &&
                    draft!.notes.any(
                      (other) =>
                          !identical(other, note) &&
                          a < (other['end_ms'] as int) &&
                          b > (other['start_ms'] as int),
                    );
                if (p == null ||
                    p < 36 ||
                    p > 96 ||
                    a == null ||
                    b == null ||
                    a < 0 ||
                    b <= a ||
                    b > draft!.durationMs ||
                    overlaps) {
                  update(
                    () => validation = c.text(
                      '请保持音符按时间排序且不重叠。',
                      'Keep notes ordered without overlaps.',
                    ),
                  );
                  return;
                }
                note.addAll({'midi': p, 'start_ms': a, 'end_ms': b});
                if (index == null) draft!.notes.add(note);
                draft!.notes.sort(
                  (a, b) =>
                      (a['start_ms'] as int).compareTo(b['start_ms'] as int),
                );
                Navigator.pop(context, true);
              },
              child: Text(c.text('保存', 'Save')),
            ),
          ],
        ),
      ),
    );
    midi.dispose();
    start.dispose();
    end.dispose();
    if (mounted && saved == true) rebuildDraft();
  }

  Future<void> save() async {
    final piece = complete;
    if (piece == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await previewKey.currentState?.stop();
      await channel.invokeMethod<void>('commitImport');
      await c.saveImportedPiece(piece);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      await channel
          .invokeMethod<void>('uncommitImport')
          .catchError((Object _) {});
      if (mounted) {
        setState(
          () => error = c.text('曲目保存失败，请重试。', 'Saving failed. Please retry.'),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text(c.text('导入 MP3 曲目', 'Import an MP3'))),
      body: QinActionPage(
        actions: [
          if (draft == null)
            QinFilledButton.icon(
              onPressed: busy ? null : choose,
              icon: const Icon(Icons.audio_file_outlined),
              label: Text(c.text('选择 MP3', 'Choose MP3')),
            )
          else
            QinFilledButton(
              onPressed: saving || complete == null ? null : save,
              child: Text(
                c.text(
                  saving ? '正在保存…' : '确认并保存曲目',
                  saving ? 'Saving…' : 'Confirm and save',
                ),
              ),
            ),
        ],
        children: [
          Text(
            c.text(
              '在本机提取单旋律。人声、和弦和伴奏可能影响识别，请试听并校对。',
              'Melody is estimated on this device. Vocals, chords and accompaniment can affect recognition. Listen and review before saving.',
            ),
          ),
          Text(
            c.text(
              '支持最长 10 分钟、100 MiB 以内的 MP3。',
              'MP3 files up to 10 minutes and 100 MiB.',
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            Text(c.text('正在解码和识别旋律…', 'Decoding and estimating melody…')),
            QinTextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(c.text('取消导入', 'Cancel import')),
            ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!),
            ),
          if (draft != null) ...[
            TextField(
              controller: title,
              onChanged: (_) => rebuildDraft(),
              decoration: InputDecoration(labelText: c.text('曲目名称', 'Title')),
            ),
            TextField(
              controller: tempo,
              keyboardType: TextInputType.number,
              onChanged: (_) => rebuildDraft(),
              decoration: InputDecoration(
                labelText: c.text(
                  '原速 BPM（估计值，可校正）',
                  'Original BPM (estimated, editable)',
                ),
              ),
            ),
            if (draft!.folded)
              Text(
                c.text(
                  '旋律超过 16 个不同音高，练习谱已折叠到中央八度。',
                  'This melody exceeds 16 distinct pitches. Training notes are folded into the middle octave.',
                ),
              ),
            const SizedBox(height: 16),
            Text(
              c.text('试听识别旋律前八小节', 'Listen to the first eight detected bars'),
            ),
            if (preview != null)
              PieceSheetPreview(
                key: previewKey,
                c: c,
                piece: preview!,
                tempo: preview!.tempo,
              ),
            const SizedBox(height: 16),
            Text(
              c.text(
                '逐音校对（点击修改，向左滑动删除）',
                'Review notes (tap to edit, swipe left to delete)',
              ),
            ),
            QinTextButton.icon(
              onPressed: () => edit(null),
              icon: const Icon(Icons.add),
              label: Text(c.text('补充音符', 'Add a note')),
            ),
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: draft!.notes.length,
                itemBuilder: (context, index) {
                  final note = draft!.notes[index];
                  return Dismissible(
                    key: ObjectKey(note),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) {
                      draft!.notes.removeAt(index);
                      rebuildDraft();
                    },
                    background: const ColoredBox(
                      color: Color(0xffac5147),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    child: ListTile(
                      onTap: () => edit(index),
                      title: Text('MIDI ${note['midi']}'),
                      subtitle: Text(
                        '${note['start_ms']}–${note['end_ms']} ms',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
