/// Accumulates only observed playback; seeks and buffering never fill gaps.
class PlaybackLedger {
  int activeMs = 0;
  final List<(int, int)> _ranges = [];
  void observe({
    required int from,
    required int to,
    required int wallMs,
    required double speed,
    required bool playing,
  }) {
    final delta = to - from;
    if (!playing ||
        wallMs <= 0 ||
        wallMs > 1500 ||
        delta <= 0 ||
        delta > wallMs * speed * 1.5 + 150) {
      return;
    }
    activeMs += (delta / speed).round().clamp(0, wallMs);
    _ranges.add((from, to));
    _ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in _ranges) {
      if (merged.isEmpty || range.$1 > merged.last.$2) {
        merged.add(range);
      } else if (range.$2 > merged.last.$2) {
        merged[merged.length - 1] = (merged.last.$1, range.$2);
      }
    }
    _ranges
      ..clear()
      ..addAll(merged);
  }

  int get coveredMs => _ranges.fold(0, (n, r) => n + r.$2 - r.$1);
}

const danceContentId = 'neuromat-fandango-4';
const danceTitle = 'Fandango · 舞蹈跟练';
const danceAsset = 'assets/video/fandango-lesson-4.webm';

class DancePart {
  const DancePart(this.id, this.title, this.asset);
  final String id, title, asset;
}

class DanceCourse {
  const DanceCourse({
    required this.id,
    required this.title,
    required this.parts,
    required this.credits,
  });
  final String id, title, credits;
  final List<DancePart> parts;
}

const chineseDanceCourse = DanceCourse(
  id: 'hkpdf-balance-six',
  title: '新平衡舞步六式',
  parts: [
    DancePart('balance-six-1', '第一部分', 'assets/video/balance-six-part-1.mp4'),
    DancePart('balance-six-2', '第二部分', 'assets/video/balance-six-part-2.mp4'),
    DancePart('balance-six-3', '第三部分', 'assets/video/balance-six-part-3.mp4'),
  ],
  credits: '新平衡舞步六式 · 第一、第二、第三部分\n素材由项目团队提供；来源及再分发授权以原权利人许可为准。\n课程参考：香港柏金逊症基金\nhttps://www.hkpdf.org.hk/physiotherapy-video',
);
const englishDanceCourse = DanceCourse(
  id: danceContentId,
  title: 'Fandango · Dance practice',
  parts: [DancePart('fandango-4', 'Fandango', danceAsset)],
  credits: 'Bora Dançar com Parkinson: Módulo Fandango (aula 4)\nRIDC NeuroMat · CC BY-SA 4.0\nOriginal video unchanged\nhttps://commons.wikimedia.org/wiki/File:Bora_Dan%C3%A7ar_com_Parkinson-_M%C3%B3dulo_Fandango_(aula_4).webm\nhttps://creativecommons.org/licenses/by-sa/4.0/',
);
DanceCourse danceCourseFor(bool chinese) =>
    chinese ? chineseDanceCourse : englishDanceCourse;

String localDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool planDue(Map<String, dynamic> plan, DateTime date) {
  final day = localDay(date);
  return plan['paused'] != true &&
      day.compareTo(plan['start'] as String) >= 0 &&
      (plan['end'] == null || day.compareTo(plan['end'] as String) <= 0) &&
      ((plan['days'] as List).isEmpty
          ? day == plan['start']
          : (plan['days'] as List).contains(date.weekday));
}

bool planExpired(Map<String, dynamic> plan, DateTime date) {
  final lastDay = (plan['days'] as List).isEmpty
      ? plan['start'] as String
      : plan['end'] as String?;
  return lastDay != null && lastDay.compareTo(localDay(date)) < 0;
}

int comparePlanSchedule(Map<String, dynamic> a, Map<String, dynamic> b) {
  final date = (a['start'] as String).compareTo(b['start'] as String);
  if (date != 0) return date;
  final timeA = (a['hour'] as int? ?? 0) * 60 + (a['minute'] as int? ?? 0);
  final timeB = (b['hour'] as int? ?? 0) * 60 + (b['minute'] as int? ?? 0);
  final time = timeA.compareTo(timeB);
  return time != 0 ? time : (a['id'] as String).compareTo(b['id'] as String);
}
