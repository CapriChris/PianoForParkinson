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
    required this.titleEn,
    required this.parts,
    required this.credits,
    required this.creditsEn,
  });
  final String id, title, titleEn, credits, creditsEn;
  final List<DancePart> parts;
  String localizedTitle(bool chinese) => chinese ? title : titleEn;
  String localizedCredits(bool chinese) => chinese ? credits : creditsEn;
  String get posterUrl =>
      'https://ccqspace.site/pd-rehab/assets/dance/v2/poster-$id.jpg';
}

const chineseDanceCourse = DanceCourse(
  id: 'hkpdf-balance-six',
  title: '新平衡舞步六式',
  titleEn: 'New Balance Six',
  parts: [
    DancePart('balance-six-1', '第一部分', 'assets/video/balance-six-part-1.mp4'),
    DancePart('balance-six-2', '第二部分', 'assets/video/balance-six-part-2.mp4'),
    DancePart('balance-six-3', '第三部分', 'assets/video/balance-six-part-3.mp4'),
  ],
  credits: '新平衡舞步六式 · 香港柏金逊症基金\n素材由项目团队提供；来源及再分发授权以原权利人许可为准。\nhttps://www.hkpdf.org.hk/physiotherapy-video',
  creditsEn: 'New Balance Six · Hong Kong Parkinson’s Disease Foundation\nProvided by the project team; source and redistribution remain subject to the rights holder’s permission.\nhttps://www.hkpdf.org.hk/physiotherapy-video',
);
const brainAndBodyCourse = DanceCourse(
  id: 'brain-and-body',
  title: '身心协调',
  titleEn: 'Brain and Body',
  parts: [
    DancePart(
      'brain-and-body-1',
      '第一部分',
      'assets/video/brain-and-body-part-1.mp4',
    ),
    DancePart(
      'brain-and-body-2',
      '第二部分',
      'assets/video/brain-and-body-part-2.mp4',
    ),
    DancePart(
      'brain-and-body-3',
      '第三部分',
      'assets/video/brain-and-body-part-3.mp4',
    ),
    DancePart(
      'brain-and-body-4',
      '第四部分',
      'assets/video/brain-and-body-part-4.mp4',
    ),
  ],
  credits: '身心协调 · 英语视频\n素材由项目团队提供；来源及再分发授权以原权利人许可为准。',
  creditsEn: 'Brain and Body · English video\nProvided by the project team; source and redistribution remain subject to the rights holder’s permission.',
);
const moveAndShoutCourse = DanceCourse(
  id: 'move-and-shout',
  title: '律动与发声',
  titleEn: 'Move and Shout',
  parts: [
    DancePart(
      'move-and-shout-1',
      '第一部分',
      'assets/video/move-and-shout-part-1.mp4',
    ),
    DancePart(
      'move-and-shout-2',
      '第二部分',
      'assets/video/move-and-shout-part-2.mp4',
    ),
    DancePart(
      'move-and-shout-3',
      '第三部分',
      'assets/video/move-and-shout-part-3.mp4',
    ),
  ],
  credits: '律动与发声 · 英语视频\n素材由项目团队提供；来源及再分发授权以原权利人许可为准。',
  creditsEn: 'Move and Shout · English video\nProvided by the project team; source and redistribution remain subject to the rights holder’s permission.',
);
const danceCourses = [
  chineseDanceCourse,
  brainAndBodyCourse,
  moveAndShoutCourse,
];
// Default selection is stable when the interface language changes.
DanceCourse danceCourseFor(bool chinese) => chineseDanceCourse;
String dancePartTitle(DancePart part, bool chinese) =>
    chinese ? part.title : 'Part ${part.id.split('-').last}';

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
