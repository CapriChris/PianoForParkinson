"""Compare the white-key staff transcription against the supplied MIDI.

The supplied file uses PPQ 220, a 55-tick score grid, and note-offs five
source ticks before written ends. Restore those ends, not tiny scored rests.
Treble (G4..A5) and bass (G2..A3) have disjoint registers in this file.
"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'tools/score_sources'


def read_midi(path):
    data = path.read_bytes()
    assert data[:4] == b'MThd'
    length, fmt, count, ppq = struct.unpack('>IHHH', data[4:14])
    assert length == 6 and fmt == 1 and ppq == 220
    pos = 14
    notes, tempos, meters = [], [], []
    for _ in range(count):
        assert data[pos:pos+4] == b'MTrk'
        length = int.from_bytes(data[pos+4:pos+8], 'big')
        track = data[pos+8:pos+8+length]
        assert len(track) == length
        pos += 8+length
        at, now, running = 0, 0, None
        active = {}

        def vlq():
            nonlocal at
            value = 0
            for _ in range(4):
                byte = track[at]
                at += 1
                value = (value << 7) | (byte & 127)
                if byte < 128:
                    return value
            raise ValueError('Invalid MIDI VLQ')

        while at < len(track):
            now += vlq()
            status = track[at]
            if status >= 128:
                at += 1
            else:
                assert running is not None
                status = running
            if status == 255:
                kind = track[at]
                at += 1
                size = vlq()
                payload = track[at:at+size]
                at += size
                if kind == 81:
                    tempos.append(int.from_bytes(payload, 'big'))
                if kind == 88:
                    meters.append(list(payload[:2]))
                running = None
            elif status in (240, 247):
                size = vlq()
                at += size
                running = None
            else:
                running = status
                kind, channel = status >> 4, status & 15
                size = 1 if kind in (12, 13) else 2
                payload = track[at:at+size]
                at += size
                identity = (channel, payload[0])
                if kind == 9 and payload[1] > 0:
                    assert identity not in active
                    active[identity] = (now, payload[1])
                elif kind == 8 or (kind == 9 and payload[1] == 0):
                    start, velocity = active.pop(identity)
                    notes.append((start, now-start, identity[1], velocity))
        assert not active
    assert pos == len(data)
    assert tempos == [666666] and meters == [[4, 2]]
    return ppq, sorted(notes)


def main():
    score = json.loads((SOURCES/'backing-score-you-are-my-sunshine.json').read_text(encoding='utf8'))
    midi_path = SOURCES/score['source']['midi_file']
    ppq, notes = read_midi(midi_path)
    unit = ppq // score['ticks_per_beat']
    melody, bass = [], []
    for start, length, pitch, velocity in notes:
        assert start % unit == 0
        assert (length+5) % unit == 0
        assert pitch % 12 in {0, 2, 4, 5, 7, 9, 11}
        assert pitch >= 67 or pitch <= 57
        assert velocity == (90 if pitch >= 67 else 66)
        (melody if pitch >= 67 else bass).append((start//unit, (length+5)//unit, pitch))
    expected_melody = [(n['start_tick'], n['duration_ticks'], n['midi'])
                       for n in score['melody_events'] if n['midi'] is not None]
    expected_bass = [(n['start_tick'], n['duration_ticks'], n['midi']) for n in score['events']]
    assert sorted(melody) == sorted(expected_melody), 'Treble differs from supplied MIDI'
    assert sorted(bass) == sorted(expected_bass), 'Bass differs from supplied MIDI'
    piece = json.loads((ROOT/'assets/content/piece-you-are-my-sunshine-001.json').read_text(encoding='utf8'))
    cursor = 0
    events = []
    for n in piece['notes']:
        if n['note_index'] >= 0:
            events.append((cursor, n['duration_ticks'], piece['key_midis'][n['note_index']]))
        cursor += n['duration_ticks']
    assert events == expected_melody
    assert cursor == 272 and piece['key_midis'] == [67, 72, 74, 76, 77, 79, 81]
    result = dict(midi_sha256=hashlib.sha256(midi_path.read_bytes()).hexdigest(),
                  ppq=ppq, reference_tempo_bpm=90, restored_note_off_ticks=5,
                  melody_notes=len(melody), bass_notes=len(bass), total_beats=cursor/4,
                  key_midis=piece['key_midis'], all_treble_white_keys=True,
                  all_bass_white_keys=True, exact_midi_comparison_after_gate_restoration=True)
    out=ROOT/'validation/audio-engine-0.1.42'
    out.mkdir(exist_ok=True)
    (out/'white-key-midi-check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
