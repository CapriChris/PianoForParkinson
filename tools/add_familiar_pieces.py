"""Author single-line practice scores; keep the existing Ode asset unchanged."""
from pathlib import Path
import hashlib
import json
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / 'assets' / 'content'
STEPS = {'G3': -3, 'A3': -2, 'B3': -1, 'C4': 0, 'D4': 1,
         'E4': 2, 'F4': 3, 'G4': 4, 'A4': 5, 'B4': 6, 'C5': 7}


def add(slug, zh, en, author_zh, author_en, keys, bars, reference, adaptation,
        *, meter=4, pickup=0, version='1.0.0'):
    notes = []
    for bar in bars:
        for item in bar.split():
            pitch, duration = item.split(':')
            ticks = int(duration)
            tied = pitch.startswith('~')
            pitch = pitch.removeprefix('~')
            key = -1 if pitch == 'r' else keys.index(pitch)
            if tied:
                if not notes or notes[-1]['note_index'] != key:
                    raise ValueError('Unmatched tie')
                notes[-1]['duration_ticks'] += ticks
            else:
                notes.append({'note_index': key, 'duration_ticks': ticks})
    piece = {
        'schema_version': 1, 'content_id': f'piece-{slug}-001', 'version': version,
        'localized_title': {'zh-Hans': zh, 'en': en},
        'localized_description': {
            'zh-Hans': f'{author_zh} · 单声部练习编配',
            'en': f'{author_en} · Single-line practice arrangement'},
        'ticks_per_beat': 2, 'beats_per_bar': meter, 'tempo_bpm': 60,
        'key_steps': [STEPS[k] for k in keys], 'notes': notes,
        'source': {
            'composer': author_en, 'reference': reference,
            'adaptation': adaptation,
            'recording': 'Salamander Grand Piano V3, Alexander Holm, CC BY 3.0; '
                         'existing samples resampled by pitch; see piano_attribution.txt',
        },
    }
    if pickup:
        piece['pickup_ticks'] = pickup
    canonical = json.dumps(piece, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    if unicodedata.normalize('NFC', canonical) != canonical:
        raise ValueError('Content must be NFC')
    piece['content_hash'] = hashlib.sha256(canonical.encode('utf-8')).hexdigest()
    path = f'assets/content/piece-{slug}-001.json'
    (ROOT / path).write_text(json.dumps(piece, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    total = sum(n['duration_ticks'] for n in notes)
    print(f'{zh}: {sum(n["note_index"] >= 0 for n in notes)} notes, '
          f'{len(notes)} events, {total} ticks, {meter}/4, {len(keys)} keys')
    return path


paths = [
    add('frere-jacques', '两只老虎', 'Frère Jacques', '法国传统民歌', 'Traditional French melody',
        ['G3', 'C4', 'D4', 'E4', 'F4', 'G4', 'A4'], [
            'C4:2 D4:2 E4:2 C4:2', 'C4:2 D4:2 E4:2 C4:2',
            'E4:2 F4:2 G4:4', 'E4:2 F4:2 G4:4',
            'G4:1 A4:1 G4:1 F4:1 E4:2 C4:2',
            'G4:1 A4:1 G4:1 F4:1 E4:2 C4:2',
            'C4:2 G3:2 C4:4', 'C4:2 G3:2 C4:4'],
        'https://noctavepiano.com/en/sheet-music/trad-frere-jacques/',
        'Complete traditional melody in C, one voice without canon or accompaniment; low G retained.'),
    add('twinkle', '小星星', 'Twinkle, Twinkle, Little Star', '法国传统旋律', 'Traditional French melody',
        ['C4', 'D4', 'E4', 'F4', 'G4', 'A4'], [
            'C4:2 C4:2 G4:2 G4:2', 'A4:2 A4:2 G4:4',
            'F4:2 F4:2 E4:2 E4:2', 'D4:2 D4:2 C4:4',
            'G4:2 G4:2 F4:2 F4:2', 'E4:2 E4:2 D4:4',
            'G4:2 G4:2 F4:2 F4:2', 'E4:2 E4:2 D4:4',
            'C4:2 C4:2 G4:2 G4:2', 'A4:2 A4:2 G4:4',
            'F4:2 F4:2 E4:2 E4:2', 'D4:2 D4:2 C4:4'],
        'https://noctavepiano.com/en/sheet-music/trad-ah-vous-dirai-je-maman/',
        'Complete 42-note traditional melody in C; quarter and half notes; accompaniment omitted.'),
    add('saints', '圣者进行曲', 'When the Saints Go Marching In', '美国传统民歌', 'Traditional American melody',
        ['C4', 'D4', 'E4', 'F4', 'G4'], [
            'r:2 C4:2 E4:2 F4:2', 'G4:8',
            'r:2 C4:2 E4:2 F4:2', 'G4:8',
            'r:2 C4:2 E4:2 F4:2', 'G4:4 E4:4',
            'C4:4 E4:4', 'D4:8',
            'r:2 E4:2 E4:2 D4:2', 'C4:6 C4:2',
            'E4:4 G4:4', 'G4:2 F4:6',
            'r:2 E4:2 F4:2 G4:2', 'E4:4 C4:4',
            'D4:8', 'C4:8'],
        'https://ivorypiano.com/songs/when-the-saints-go-marching-in',
        'Complete single-pass 32-note C-major melody, straight quarter-note rhythm; '
        'onsets and durations checked against the arranger\'s printed piano score and '
        'machine-readable melody. Opening phrase G lasts four beats; final cadence E C D C. '
        'Replaces the earlier short-note recorder adaptation.', version='1.0.1'),
    add('happy-birthday', '生日快乐', 'Happy Birthday to You', '米尔德里德·希尔、帕蒂·希尔',
        'Mildred and Patty Hill', ['G3', 'A3', 'B3', 'C4', 'D4', 'E4', 'F4', 'G4'], [
            'G3:1 G3:1', 'A3:2 G3:2 C4:2', 'B3:4 G3:1 G3:1',
            'A3:2 G3:2 D4:2', 'C4:4 G3:1 G3:1', 'G4:2 E4:2 C4:2',
            'B3:2 A3:2 F4:1 F4:1', 'E4:2 C4:2 D4:2', 'C4:4'],
        'https://ivorypiano.com/songs/happy-birthday',
        'Complete melody in C, down one octave from the common G4-G5 version; '
        '3/4 meter, equal eighth-note pickup pairs and complementary final bar.', meter=3, pickup=2),
    add('you-are-my-sunshine', '你是我的阳光', 'You Are My Sunshine',
        '吉米·戴维斯、查尔斯·米切尔', 'Jimmie Davis and Charles Mitchell',
        ['G3', 'C4', 'D4', 'E4', 'F4', 'G4', 'A4'], [
            'G3:2 C4:2 D4:2', 'E4:4 E4:4', 'r:2 E4:2 D4:2 E4:2',
            'C4:4 C4:4', 'r:2 C4:2 D4:2 E4:2', 'F4:4 A4:4',
            'r:2 A4:2 G4:2 F4:2', 'E4:8', 'r:2 C4:2 D4:2 E4:2',
            'F4:4 A4:4', 'r:2 A4:2 G4:2 F4:2', 'E4:4 C4:4',
            'r:2 G3:2 C4:2 D4:2', 'E4:6 F4:2', 'D4:4 D4:2 E4:2', 'C4:8', 'r:2'],
        'https://www.loganhone.com/Library/sheetmusic/aug152024_Community_Band_Songbook-Vocals.pdf#page=54',
        'Chorus melody only, no lyrics, verses or accompaniment; transposed from the printed '
        'F-major staff to C major, with rests and a three-beat pickup retained; one-beat closing rest. '
        'Pitch correction checked against the printed staff and PangfunJ Studio MusicXML '
        '(https://pangfunjstudio.com/wp-content/uploads/2024/09/you-are-my-sunshine.mxl); '
        'the original reference pickup, rhythm and phrasing are retained.',
        pickup=6, version='1.0.1'),
]
catalog_path = CONTENT / 'piece-catalog.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
catalog['paths'] = list(dict.fromkeys(catalog['paths'] + paths))
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
