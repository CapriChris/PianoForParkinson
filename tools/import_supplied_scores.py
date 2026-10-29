"""Literal, reviewable transcription of the six user-supplied staff images.

Durations are quarter beats; r is a rest, + denotes simultaneous bass notes,
and ~ at a note's start continues the preceding tied note. Repeat order is
explicit. No transposition, reharmonisation or inferred accompaniment.
"""
from fractions import Fraction
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'tools/score_sources'
TEMP = Path('C:/Users/29564/AppData/Local/Temp')

SCORES = {
 'ode-to-joy': dict(image='d3630c78-7549-4e3d-955b-7e835b1390d1', user='191626', score='182061',
  treble=[
   'E4 F4 G4',  # replaced below by the fully repeated first attack
   'G4 F4 E4 D4', 'C4 C4 D4 E4', 'E4:1.5 D4:.5 D4:2',
   'E4 E4 F4 G4','G4 F4 E4 D4','C4 C4 D4 E4','D4:1.5 C4:.5 C4:2',
   'D4 D4 E4 C4','D4 E4:.5 F4:.5 E4 C4','D4 E4:.5 F4:.5 E4 D4','C4 D4 r:2',
   'E4 E4 F4 G4','G4 F4 E4 D4','C4 C4 D4 E4','D4:1.5 C4:.5 C4:2'],
  bass=['C3+G3:4','B2+G3:4','E3+G3:2 D3 C3','G3:4',
        'C3+G3:4','B2+G3:4','E3+G3:2 D3 C3','F3+G3:1.5 E3+G3:.5 E3+G3:2',
        'B2+G3:2 C3+G3:2','B2+G3:2 C3+G3:2','B2+G3:2 G#3:2','A3 F#3 G3:2',
        'C3+G3:4','B2+G3:4','E3+G3:2 D3 C3','F3+G3:1.5 E3+G3:.5 E3+G3:2']),
 'frere-jacques': dict(image='ed2169e8-8470-45d7-8de4-1760054a9d70', user='259021',score='5856883',
  treble=['C4 D4 E4 C4','E4 F4 G4:2','G4:.75 A4:.25 G4:.5 F4:.5 E4 C4','C4 G4 C4:2'],
  bass=['C3:2 E3:2','E3:2 G3:2','G3:2 E3:2','r G3:2 r'], order=[0,0,1,1,2,2,3,3]),
 'twinkle': dict(image='a364ef65-1d25-4728-9840-e3b1e07dc146', user='110059', score='1525331',
  treble=['C4 C4 G4 G4','A4 A4 G4:2','F4 F4 E4 E4','D4 D4 C4:2',
          'G4 G4 F4 F4','E4 E4 D4:2','G4 G4 F4 F4','E4 E4 D4:2',
          'C4 C4 G4 G4','A4 A4 G4:2','F4 F4 E4 E4','D4 D4 C4:2'],
  bass=['E3 E3 E3 E3','F3 F3 E3:2','D3 D3 C3 C3','B2 B2 C3:2',
        'E3 E3 D3 D3','C3 C3 B2:2','E3 E3 D3 D3','C3 C3 G2:2',
        'E3 E3 E3 E3','F3:.5 G3:.5 A3:.5 B3:.5 C4:2','D3 A3 G3 C3','G3 G2 C3:2']),
 'saints': dict(image='c2475317-5175-4050-a20e-eeb046939ca1',user='30689505',score='5468872',pickup=3,
  treble=['C4 E4 F4','G4:4','~G4 C4 E4 F4','G4:4','~G4 C4 E4 F4',
          'G4:2 E4:2','C4:2 E4:2','D4:4','~D4 r E4 D4','C4:2 C4:2','E4:2 G4:2',
          'G4 F4:3','~F4:2 E4 F4','G4:2 E4:2','D4:2 D4:2','C4:4','~C4'],
  bass=['r:3','r C3+E3+G3 C3+E3+G3 C3+E3+G3','C3+E3+G3 r:3',
        'r C3+E3+G3 C3+E3+G3 C3+E3+G3','C3+E3+G3 r:3',
        'r C3+E3+G3 r C3+E3+G3','r C3+E3+G3 r C3+E3+G3',
        'r B2+F3+G3 B2+F3+G3 B2+F3+G3','B2+F3+G3 r:3',
        'r C3+E3+G3 r C3+E3+G3','r C3+E3+G3 r C3+E3+G3',
        'r:2 C3+F3+A3 C3+F3+A3','C3+F3+A3:2 r:2',
        'r C3+E3+G3 r C3+E3+G3','r B2+F3+G3 r B2+F3+G3',
        'r C3+E3+G3 C3+E3+G3 C3+E3+G3','C3+E3+G3'],order=list(range(17))*2),
 'happy-birthday':dict(image='d6b7d0b9-5ff4-41d9-b78f-e09087e5df6d',user='32960140',score='5847891',meter=3,
  treble=['r r G4:.5 G4:.5','A4 G4 C5','B4:2 G4:.5 G4:.5','A4 G4 D5','C5:2 G4:.5 G4:.5',
          'G5 E5 C5','B4 G4 A4:.5 B4:.5','C5 C5 A4','D5:2 G4:.5 G4:.5','A4 G4 C5',
          'B4:2 G4:.5 G4:.5','A4 G4 D5','C5:2 G4:.5 G4:.5','G5 E5 C5','B4 A4 F5:.5 F5:.5',
          'E5 C5 D5','C5:2 G4:.5 G4:.5','G5 E5 C5','B4 A4 F5:.5 F5:.5','E5 C5 D5',
          'C5:3','C5:2 r','r:3'],
  bass=['r:3','C3 E3 G3','D3 F3 G3','B2 D3 G3','C3 E3 G3',
        'C3 E3 G3','F3 A3 C4','D3 F#3 C4','G3 B3 D4','C3 E3 G3',
        'D3 F3 G3','B2 D3 G3','C3 E3 G3','C3 E3 G3','F3 A3 C4',
        'G3 D4 B3','C4 G3 E3','C3 E3 G3','F3 A3 C4','G3 C4+E4 G3+B3+D4',
        'C3 E3 G3','C4:2 r','r:3']),
 'you-are-my-sunshine':dict(image='1f843cfb-28d1-426e-866a-5a1ef61dd088',
  image_file='supplied-you-are-my-sunshine-white-keys.png',
  midi_file='You_Are_My_Sunshine_white_keys.mid', content_version='2.1.0',
  reference='User-supplied white-key score and MIDI, 2026-10-26',
  treble=['r:2 r:.5 G4:.5 C5:.5 D5:.5',
          'E5 E5:1.5 E5:.5 D5:.5 E5:.5',
          'C5 C5:1.5 C5:.5 D5:.5 E5:.5',
          'F5 A5:1.5 A5:.5 G5:.5 F5:.5','E5:2 ~E5:.5 C5:.5 D5:.5 E5:.5',
          'F5 A5:1.5 A5:.5 G5:.5 F5:.5','E5 C5:1.5 C5:.5 C5:.5 D5:.5',
          'E5:1.5 F5:.5 D5 D5:.5 E5:.5','C5:2 r:.5 G4:.5 C5:.5 D5:.5',
          'E5 E5:1.5 E5:.5 D5:.5 E5:.5','C5 C5:1.5 C5:.5 D5:.5 E5:.5',
          'F5 A5:1.5 A5:.5 G5:.5 F5:.5','E5:2 ~E5:.5 C5:.5 D5:.5 E5:.5',
          'F5 A5:1.5 A5:.5 G5:.5 F5:.5','E5 C5:1.5 C5:.5 C5:.5 D5:.5',
          'E5:1.5 F5:.5 D5 D5:.5 E5:.5','C5:4'],
  bass=['r:4','C3 E3+G3 C3 E3+G3','C3 E3+G3 C3 E3+G3','C3 F3+A3 C3 F3+A3',
        'C3 E3+G3 C3 E3+G3','C3 F3+A3 C3 F3+A3','C3 E3+G3 C3 E3+G3',
        'G2 C3+E3 G2 B2+D3','C3 E3+G3 C3 E3+G3',
        'C3:.5 G3:.5 E3:.5 G3:.5 C3:.5 G3:.5 E3:.5 G3:.5',
        'C3:.5 G3:.5 E3:.5 G3:.5 C3:.5 G3:.5 E3:.5 G3:.5',
        'C3:.5 A3:.5 F3:.5 A3:.5 C3:.5 A3:.5 F3:.5 A3:.5',
        'C3:.5 G3:.5 E3:.5 G3:.5 C3:.5 G3:.5 E3:.5 G3:.5',
        'C3:.5 A3:.5 F3:.5 A3:.5 C3:.5 A3:.5 F3:.5 A3:.5',
        'C3:.5 G3:.5 E3:.5 G3:.5 C3:.5 G3:.5 E3:.5 G3:.5',
        'G2:.5 E3:.5 C3:.5 E3:.5 G2:.5 D3:.5 B2:.5 D3:.5',
        'C3:.5 G3:.5 E3:.5 G3:.5 C3:2'])
}
SCORES['ode-to-joy']['treble'][0] = 'E4 E4 F4 G4'


def canonical(x):
    return json.dumps(x, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def midi(note):
    if note == 'r':
        return None
    natural = {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}[note[0]]
    return (int(note[-1])+1)*12 + natural + note[1:-1].count('#') - note[1:-1].count('b')


def step(note):
    return (int(note[-1])-4)*7 + 'CDEFGAB'.index(note[0])


def tokens(bar):
    for token in bar.split():
        note, _, duration = token.partition(':')
        ticks = Fraction(duration or '1') * 4
        assert ticks.denominator == 1
        yield note, int(ticks)


def main(selected=None, audit_version='0.1.39'):
    report_path=ROOT/f'validation/audio-engine-{audit_version}/supplied-score-import.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_by_slug={r['slug']:r for r in json.loads(report_path.read_text(encoding='utf8'))} if report_path.exists() else {}
    for slug, spec in SCORES.items():
        if selected is not None and slug not in selected:
            continue
        image = SOURCES / spec.get('image_file', f'supplied-{slug}.png')
        if not image.exists():
            shutil.copyfile(TEMP / f'codex-clipboard-{spec["image"]}.png', image)
        image_hash = hashlib.sha256(image.read_bytes()).hexdigest()
        order = spec.get('order', list(range(len(spec['treble']))))
        melody, bass, bar_lengths = [], [], []
        now = 0
        for iteration, bar in enumerate(order):
            top, low = list(tokens(spec['treble'][bar])), list(tokens(spec['bass'][bar]))
            length = sum(t for _, t in top)
            assert length == sum(t for _, t in low), (slug, bar+1, 'voice length mismatch')
            assert length <= spec.get('meter',4)*4
            bar_lengths.append(length)
            offset = now
            for note, ticks in top:
                tied = note.startswith('~')
                name = note.lstrip('~')
                pitch = midi(name)
                if tied:
                    assert melody and melody[-1]['midi'] == pitch and melody[-1]['start_tick']+melody[-1]['duration_ticks'] == offset
                    melody[-1]['duration_ticks'] += ticks
                else:
                    melody.append(dict(midi=pitch, spelling=name, start_tick=offset, duration_ticks=ticks,
                                       source_measure=str(bar+1), pass_measure=iteration+1))
                offset += ticks
            offset = now
            for chord, ticks in low:
                for name in chord.split('+'):
                    pitch = midi(name)
                    if pitch is not None:
                        bass.append(dict(midi=pitch, start_tick=offset, duration_ticks=ticks,
                                         source_part='P1', source_staff='2', source_voice='1',
                                         source_measure=str(bar+1), pass_measure=iteration+1, staccato=False))
                offset += ticks
            now += length
        key_names = {n['midi']:n['spelling'] for n in melody if n['midi'] is not None}
        keys = sorted(key_names)
        piece_path = ROOT / f'assets/content/piece-{slug}-001.json'
        piece = json.loads(piece_path.read_text(encoding='utf8'))
        piece.pop('content_hash',None); piece.pop('accompaniment',None)
        version = spec.get('content_version', '2.0.0')
        piece.update(version=version, ticks_per_beat=4, beats_per_bar=spec.get('meter',4),
                     pickup_ticks=spec.get('pickup',0)*4,
                     key_midis=keys, key_steps=[step(key_names[n]) for n in keys],
                     notes=[dict(note_index=-1 if n['midi'] is None else keys.index(n['midi']),
                                 duration_ticks=n['duration_ticks']) for n in melody])
        source = dict(kind='user_image',file=image.name,reference=spec.get('reference') or f'https://musescore.com/user/{spec["user"]}/scores/{spec["score"]}',
                      content_version=version,rights='User-supplied score image; internal prototype transcription. No redistribution license inferred.',
                      transcription='Literal treble and bass staves, original pitch, ties merged, written repeats unfolded.',
                      ticks_per_quarter=4, playback_order=[n+1 for n in order])
        if spec.get('midi_file'):
            midi_path = SOURCES / spec['midi_file']
            source.update(midi_file=midi_path.name,
                          midi_sha256=hashlib.sha256(midi_path.read_bytes()).hexdigest(),
                          reference_tempo_bpm=90,
                          adaptation='White-key C-major version supplied by the user; both staves retained. '
                                     'MIDI note-offs precede written ends by five source ticks; score durations restored.')
            piece['source']['reference'] = source['reference']
            piece['source']['adaptation'] = source['adaptation']
        piece['score_source'] = dict(source, sha256=image_hash)
        piece['content_hash'] = hashlib.sha256(canonical(piece).encode()).hexdigest()
        piece_path.write_text(json.dumps(piece, ensure_ascii=False, indent=2)+'\n',encoding='utf8')
        document = dict(schema_version=1,content_id=piece['content_id'],total_ticks=now,
                        ticks_per_beat=4,source=source,source_sha256=image_hash,
                        treble_bars=spec['treble'],bass_bars=spec['bass'],bar_ticks=bar_lengths,
                        melody_events=melody,events=bass)
        document['score_hash']=hashlib.sha256(canonical(document).encode()).hexdigest()
        (SOURCES / f'backing-score-{slug}.json').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
        report_by_slug[slug]=dict(slug=slug,notes=len(melody),bass_notes=len(bass),ticks=now,beats=now/4,key_midis=keys,bar_ticks=bar_lengths,source_sha256=image_hash)
        print(slug,len(melody),'events,',len(bass),'bass notes,',now/4,'beats',flush=True)
    report_path.write_text(json.dumps([report_by_slug[s] for s in SCORES if s in report_by_slug],indent=2)+'\n',encoding='utf8')


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--pieces',nargs='+',choices=list(SCORES),default=list(SCORES))
    parser.add_argument('--audit-version',default='0.1.39')
    args=parser.parse_args()
    main(args.pieces,args.audit_version)
