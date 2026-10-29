"""Import individually selected, written accompaniment voices into exact ticks.

Source MusicXML is retained with hashes. This does not generate notes from chord
names or reuse the former accompaniment pattern across songs.
"""
from fractions import Fraction
from pathlib import Path
import hashlib
import json

from musicxml_notes import read_score

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'tools/score_sources'

# A selection is (part, staff or None, semitone transposition).
RECIPES = {
    'ode-to-joy': {
        'file': 'maestro-ode.musicxml',
        'reference': 'https://maestroscore.app/examples/',
        'download': 'https://maestroscore.app/esempi/inno-alla-gioia.musicxml',
        'arranger': 'Maestro', 'rights': 'Publisher permits use, modification and sharing of the arrangements.',
        'selections': [('P1', '2', -2)], 'measures': list(range(1, 9)),
        'ticks_per_quarter': 2, 'tick_offset': 0,
        'adaptation': 'Piano left-hand staff, first eight bars; D major to C major. '
                      'Source right-hand melody is one octave above the app after transposition.',
        'melody_selection': ('P1', '1', -14), 'melody_check': 'exact',
    },
    'frere-jacques': {
        'file': 'noctave-frere.mxl',
        'reference': 'https://noctavepiano.com/en/sheet-music/trad-frere-jacques/',
        'download': 'https://noctavepiano.com/partitions/trad-frere-jacques/trad-frere-jacques.mxl',
        'arranger': 'Noctave', 'rights': 'CC0 1.0; source MusicXML retains the publisher rights statement.',
        'selections': [('P1', '1', -12)], 'measures': list(range(1, 9)),
        'ticks_per_quarter': 2, 'tick_offset': 0,
        'adaptation': 'The reference places the tune in the bass staff. Its sustained right-hand '
                      'counterline is lowered one octave for the backing; the app tune remains '
                      'one octave above the source bass melody. No canon or added chord pattern.',
        'melody_selection': ('P1', '2', 12), 'melody_check': 'exact',
    },
    'twinkle': {
        'file': 'noctave-twinkle.mxl',
        'reference': 'https://noctavepiano.com/en/sheet-music/trad-ah-vous-dirai-je-maman/',
        'download': 'https://noctavepiano.com/partitions/trad-ah-vous-dirai-je-maman/trad-ah-vous-dirai-je-maman.mxl',
        'arranger': 'Noctave', 'rights': 'CC0 1.0; source MusicXML retains the publisher rights statement.',
        'selections': [('P1', '2', 0)], 'measures': list(range(1, 13)),
        'ticks_per_quarter': 2, 'tick_offset': 0,
        'adaptation': 'All twelve bars of the written left hand; whole and half-note basses '
                      'retained without adding generic offbeat chords.',
        'melody_selection': ('P1', '1', 0), 'melody_check': 'exact',
    },
    'saints': {
        'file': 'maestro-saints.musicxml',
        'reference': 'https://maestroscore.app/examples/',
        'download': 'https://maestroscore.app/esempi/when-the-saints.musicxml',
        'arranger': 'Maestro', 'rights': 'Publisher permits use, modification and sharing of the arrangements.',
        'selections': [('P3', '1', -5), ('P4', None, 7)],
        'measures': list(range(1, 17)), 'ticks_per_quarter': 2, 'tick_offset': 0,
        'adaptation': 'Written jazz piano chord staff plus written walking double-bass part, '
                      'both played with piano samples. F major to C major; concert bass raised '
                      'an octave to keep it light. Horns, drums and piano pedal bass omitted. '
                      'Selected voices contain quarter/whole notes, so no swing timing is added. '
                      'After emulator recording review, six close semitone chord neighbors '
                      'of the melody are temporarily omitted; walking bass and other chord '
                      'voices are retained. This avoids same-register collisions without '
                      'adding a lower voice whose harmonics can recreate the neighbor tone.',
        'content_version': '1.3.1',
        'omit_close_neighbors': True,
        'melody_selection': ('P1', '1', -5), 'melody_check': 'exact',
    },
    'happy-birthday': {
        'file': 'artform-birthday.mxl',
        'reference': 'https://jamescarterpiano.com/sheet-music/traditional/happy-birthday/',
        'download': 'https://jamescarterpiano.com/notation/scores/happy-birthday.mxl',
        'arranger': 'Manjuprasad; source distributed by Artform / James Carter',
        'rights': 'Artform labels its downloadable score public domain. MusicXML credits '
                  'Manjuprasad and points to musescore.com/user/27657013/scores/5282628.',
        'selections': [('P1', '2', 0)], 'measures': list(range(0, 9)),
        'ticks_per_quarter': 2, 'tick_offset': 0,
        'adaptation': 'First verse left hand only, ending at beat 24; repetitions and coda '
                      'omitted. Source dotted pickup pairs differ from the app equal eighths; '
                      'left-hand quarter-note positions align. Source splits one C melody note '
                      'into repeated syllables; the app tune is unchanged.',
        'melody_check': 'bar-aligned variant; app melody unchanged',
    },
    'you-are-my-sunshine': {
        'file': 'pangfunj-sunshine.mxl',
        'reference': 'https://pangfunjstudio.com/sheet-music/youre-my-sunshine-jimmie-davis-and-charles-mitchell/',
        'download': 'https://pangfunjstudio.com/wp-content/uploads/2024/09/you-are-my-sunshine.mxl',
        'arranger': 'PangfunJ Studio',
        'rights': 'PERSONAL_LEARNING_ONLY: publisher disclosure permits personal learning '
                  'and excludes resale; used for the current internal learning demo, '
                  'not represented as an unrestricted redistribution license.',
        'selections': [('P1', '2', -12)], 'measures': list(range(1, 17)),
        'ticks_per_quarter': 4, 'tick_offset': -2,
        'adaptation': 'First sixteen source bars only; written left-hand broken chords '
                      'lowered one octave. Source 2/4 quarters become app half notes. '
                      'Initial half-beat rest removed to match the app three-beat pickup; '
                      'backing remains silent during that pickup. App closing rest and '
                      'its extra low-G pickup variant are retained.',
        'melody_check': '37 source notes align; app has one extra low-G pickup note',
    },
}


def selected_notes(score, recipe, selection):
    part, staff, transpose = selection
    for measure in score[part]['measures']:
        if int(measure['number']) not in recipe['measures']:
            continue
        for note in measure['notes']:
            if staff is None or note['staff'] == staff:
                yield part, note, transpose


def app_melody(piece):
    midi = [55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72]
    result = []
    start = 0
    for n in piece['notes']:
        if n['note_index'] >= 0:
            step = piece.get('key_steps', [0, 1, 2, 3, 4])[n['note_index']]
            result.append((start, n['duration_ticks'], midi[step + 3]))
        start += n['duration_ticks']
    return result


def exact(value):
    assert value.denominator == 1, f'Unrepresentable tick: {value}'
    return value.numerator


def main(audit_version='0.1.38'):
    reports = []
    for slug, recipe in RECIPES.items():
        saved = SOURCES / f'backing-score-{slug}.json'
        if saved.exists() and json.loads(saved.read_text(encoding='utf-8')).get('source', {}).get('kind') == 'user_image':
            print(slug, 'retaining user-supplied transcription')
            continue
        source = SOURCES / recipe['file']
        score = read_score(source)
        piece = json.loads((ROOT / f'assets/content/piece-{slug}-001.json').read_text(encoding='utf-8'))
        total = sum(n['duration_ticks'] for n in piece['notes'])
        factor = recipe['ticks_per_quarter']
        offset = recipe['tick_offset']
        events = []
        for selection in recipe['selections']:
            for part, n, transpose in selected_notes(score, recipe, selection):
                start = exact(n['start'] * factor) + offset
                end = start + exact(n['duration'] * factor)
                if start >= total or end <= 0:
                    continue
                events.append({
                    'start_tick': max(0, start), 'duration_ticks': min(total, end) - max(0, start),
                    'midi': n['midi'] + transpose,
                    'source_part': part, 'source_staff': n['staff'],
                    'source_voice': n['voice'], 'source_measure': n['measure'],
                    'staccato': n['staccato'],
                })
        events.sort(key=lambda n: (n['start_tick'], n['midi'], n['duration_ticks']))
        source_count = len(events)
        adjustments = []
        if recipe.get('omit_close_neighbors'):
            opened = []
            tune = app_melody(piece)
            for event in events:
                active = next((m for t, d, m in tune
                               if t <= event['start_tick'] < t + d), None)
                if event['source_part'] == 'P3' and active is not None and abs(event['midi'] - active) == 1:
                    original = event['midi']
                    adjustments.append({'start_tick': event['start_tick'], 'reference_midi': original,
                                        'melody_midi': active, 'action': 'omit_neighbor_voice',
                                        'source_part': event['source_part'],
                                        'source_measure': event['source_measure']})
                    continue
                opened.append(event)
            events = sorted(opened, key=lambda n: (n['start_tick'], n['midi'], n['duration_ticks']))
        if recipe['melody_check'] == 'exact':
            actual = sorted((exact(n['start'] * factor) + offset,
                             exact(n['duration'] * factor), n['midi'] + transpose)
                            for _, n, transpose in selected_notes(score, recipe, recipe['melody_selection']))
            assert actual == sorted(app_melody(piece)), f'{slug}: source melody mismatch'
        if slug == 'you-are-my-sunshine':
            melody = [(exact(n['start'] * factor) + offset, exact(n['duration'] * factor), n['midi'] - 12)
                      for _, n, _ in selected_notes(score, recipe, ('P1', '1', 0))]
            assert len(melody) == 37
            assert set(melody).issubset(set(app_melody(piece)))
        assert events and all(0 <= e['start_tick'] < total and 21 <= e['midi'] <= 108
                              and e['duration_ticks'] > 0 for e in events)
        manifest = {
            'schema_version': 1, 'content_id': piece['content_id'], 'total_ticks': total,
            'source': {k: v for k, v in recipe.items() if k not in ('melody_selection',)},
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'events': events,
        }
        if adjustments:
            manifest['source_note_count'] = source_count
            manifest['voicing_adjustments'] = adjustments
        canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        manifest['score_hash'] = hashlib.sha256(canonical.encode()).hexdigest()
        (SOURCES / f'backing-score-{slug}.json').write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        reports.append({'id': piece['content_id'], 'events': len(events),
                        'melody_check': recipe['melody_check'], 'score_hash': manifest['score_hash']})
        print(slug, len(events), 'literal score notes;', recipe['melody_check'])
    (ROOT / f'validation/score-backed-import-{audit_version}.json').write_text(
        json.dumps(reports, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
