"""Read literal pitched notes from saved MusicXML, including chords and ties.

Times are exact quarter-note Fractions. No accompaniment is inferred from chord
symbols, slash notation or generated patterns.
"""
from fractions import Fraction
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

STEPS = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def read_score(path):
    path = Path(path)
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            container = ET.fromstring(z.read('META-INF/container.xml'))
            target = next(x.attrib['full-path'] for x in container.iter()
                          if x.tag.endswith('rootfile'))
            root = ET.fromstring(z.read(target))
    else:
        root = ET.parse(path).getroot()
    names = {p.attrib['id']: p.findtext('part-name')
             for p in root.findall('part-list/score-part')}
    result = {}
    for part in root.findall('part'):
        divisions = 1
        bar_beats = Fraction(4)
        start = Fraction(0)
        transpose = 0
        measures = []
        active_ties = {}
        for measure in part.findall('measure'):
            cursor = maximum = Fraction(0)
            last_onset = Fraction(0)
            notes = []
            for item in measure:
                if item.tag == 'attributes':
                    divisions = int(item.findtext('divisions', str(divisions)))
                    time = item.find('time')
                    if time is not None:
                        bar_beats = Fraction(int(time.findtext('beats')) * 4,
                                             int(time.findtext('beat-type')))
                    trans = item.find('transpose')
                    if trans is not None:
                        transpose = int(trans.findtext('chromatic', '0')) + \
                                    12 * int(trans.findtext('octave-change', '0'))
                elif item.tag in ('backup', 'forward'):
                    step = Fraction(int(item.findtext('duration')), divisions)
                    cursor += step if item.tag == 'forward' else -step
                    if cursor < 0:
                        raise ValueError('MusicXML cursor before measure start')
                    maximum = max(maximum, cursor)
                elif item.tag == 'note':
                    if item.find('grace') is not None:
                        continue
                    duration = Fraction(int(item.findtext('duration', '0')), divisions)
                    onset = last_onset if item.find('chord') is not None else cursor
                    if item.find('chord') is None:
                        last_onset = cursor
                        cursor += duration
                    maximum = max(maximum, onset + duration, cursor)
                    pitch = item.find('pitch')
                    if pitch is None:
                        continue
                    midi = (int(pitch.findtext('octave')) + 1) * 12 + \
                           STEPS[pitch.findtext('step')] + \
                           int(pitch.findtext('alter', '0')) + transpose
                    staff = item.findtext('staff', '1')
                    voice = item.findtext('voice', '1')
                    tie = {t.attrib['type'] for t in item.findall('tie')}
                    key = (staff, voice, midi)
                    previous = active_ties.get(key)
                    if 'stop' in tie and previous is not None and \
                            previous['start'] + previous['duration'] == start + onset:
                        previous['duration'] += duration
                        if 'start' not in tie:
                            del active_ties[key]
                        continue
                    note = {'start': start + onset, 'duration': duration,
                            'midi': midi, 'staff': staff, 'voice': voice,
                            'measure': measure.attrib.get('number'),
                            'staccato': item.find('.//staccato') is not None}
                    notes.append(note)
                    if 'start' in tie:
                        active_ties[key] = note
            length = maximum if measure.attrib.get('implicit') == 'yes' else max(bar_beats, maximum)
            measures.append({'number': measure.attrib.get('number'),
                             'start': start, 'length': length, 'notes': notes})
            start += length
        result[part.attrib['id']] = {'name': names.get(part.attrib['id']),
                                     'measures': measures}
    return result
