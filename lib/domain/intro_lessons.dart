import 'dart:math';

class IntroLesson {
  const IntroLesson(this.id, this.zh, this.en, this.rules);
  final String id, zh, en;
  final List<({String zh, String en})> rules;
  static const version = '1.0.0';
  static const all = [
    IntroLesson('T1', '按键发声', 'Keys and sound', [
      (zh: '轻触一枚琴键，就会发出一个音。', en: 'Touch a key to hear a note.'),
      (
        zh: '按住琴键，条满后再松开。',
        en: 'Hold the key until the bar fills, then release.',
      ),
      (
        zh: '松开后再按，可以再次弹出这个音。',
        en: 'Release and press again to play the note again.',
      ),
    ]),
    IntroLesson('T2', '高低音', 'Low and high notes', [
      (zh: '左边琴键的音较低。', en: 'Keys on the left play lower notes.'),
      (zh: '右边琴键的音较高。', en: 'Keys on the right play higher notes.'),
      (
        zh: '从左向右弹，听听音怎样变高。',
        en: 'Play from left to right to hear the notes rise.',
      ),
    ]),
    IntroLesson('T3', '节拍与等待', 'Beat and wait', [
      (
        zh: '看亮起的拍点，感受均匀的节拍。',
        en: 'Watch the highlighted beats to feel a steady pulse.',
      ),
      (zh: '看到“弹奏”，按亮起的琴键。', en: 'For Play, press the highlighted key.'),
      (zh: '看到“等待”，让琴键保持松开。', en: 'For Wait, leave all keys released.'),
    ]),
  ];

  static IntroLesson byId(String id) => all.firstWhere(
    (lesson) => lesson.id == id,
    orElse: () => throw ArgumentError.value(id, 'lessonId'),
  );
}

class LessonDemo {
  const LessonDemo(this.notes, {this.holdMs = 400});
  final List<int?> notes;
  final int holdMs;
  static const intervalMs = 1500;
  int get durationMs => notes.length * intervalMs;

  static LessonDemo create(String lessonId, int page, {Random? random}) {
    IntroLesson.byId(lessonId);
    if (page < 0 || page > 2) throw RangeError.range(page, 0, 2);
    final rng = random ?? Random();
    if (lessonId == 'T1') {
      final key = rng.nextInt(3);
      return LessonDemo(
        page == 2 ? [key, key] : [key],
        holdMs: page == 0 ? 100 + rng.nextInt(101) : 400,
      );
    }
    if (lessonId == 'T2') {
      return LessonDemo(
        page == 0
            ? [0]
            : page == 1
            ? [2]
            : [0, 1, 2],
      );
    }
    return LessonDemo(
      page == 0
          ? [null, null, null, null]
          : page == 1
          ? [0, 0, 0, 0]
          : [0, null, 0, null],
    );
  }
}
