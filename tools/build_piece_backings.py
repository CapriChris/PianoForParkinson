"""Render individually sourced, written accompaniments with the attributed local samples.

Run after add_familiar_pieces.py (and build_piano_pieces.dart if rebuilding Ode).
The importer verifies saved source scores and exports their literal note events.
Render each supported tempo independently: no phone-side time stretching.
The Ogg/Vorbis files contain bass/chords only, with exact score lengths.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import threading
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
try:
    import soundfile as sf
except ModuleNotFoundError:
    sys.path.insert(0, str(ROOT / 'tmp/audio-tooling'))
    import soundfile as sf
RATE = 22050
SAMPLE_MIDI = [60, 62, 64, 65, 67, 69, 71]
SCORE_IDS = ['ode-to-joy', 'frere-jacques', 'twinkle', 'saints',
             'happy-birthday', 'you-are-my-sunshine']


def read_samples():
    bank = ROOT / 'assets/content/piano_bank.json'
    if bank.exists():
        manifest = json.loads(bank.read_text(encoding='utf8'))
        result = []
        for item in manifest['samples']:
            data, rate = sf.read(ROOT / item['path'])
            result.append((item['midi'], data, rate, item['loop_start'], item['loop_end'], item['crossfade_frames']))
        return result
    result = []
    for i in range(7):
        with wave.open(str(ROOT / f'assets/audio/note_{i}.wav')) as w:
            assert w.getnchannels() == 1 and w.getsampwidth() == 2
            result.append((SAMPLE_MIDI[i], np.frombuffer(w.readframes(w.getnframes()), '<i2')
                           .astype(np.float64) / 32768, w.getframerate(), 0, 0, 0))
    return result


def render(slug, samples):
    path = ROOT / f'assets/content/piece-{slug}-001.json'
    piece = json.loads(path.read_text(encoding='utf-8'))
    total = sum(n['duration_ticks'] for n in piece['notes'])
    score_path = ROOT / f'tools/score_sources/backing-score-{slug}.json'
    score = json.loads(score_path.read_text(encoding='utf-8'))
    assert score['content_id'] == piece['content_id'] and score['total_ticks'] == total
    source = ROOT / 'tools/score_sources' / score['source']['file']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == score['source_sha256']
    score_body = dict(score)
    score_hash = score_body.pop('score_hash')
    assert hashlib.sha256(json.dumps(score_body, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest() == score_hash
    events = score['events']
    variants = {}
    for tempo in [40, 50, 60, 70, 80]:
        seconds_per_tick = 60 / tempo / piece['ticks_per_beat']
        mix = np.zeros(round(total * RATE * seconds_per_tick), dtype=np.float64)
        for event in events:
            tick = event['start_tick']
            duration = event['duration_ticks'] * (.60 if event['staccato'] else 1)
            midi = event['midi']
            gain = .72 if event['source_part'] == 'P4' or midi < 53 else .48
            sample_index = min(range(len(samples)), key=lambda i: abs(samples[i][0] - midi))
            root, data, source_rate, loop_start, loop_end, crossfade = samples[sample_index]
            ratio = 2 ** ((midi - root) / 12)
            count = round((duration * seconds_per_tick + .26) * RATE)
            offsets = np.arange(count) * source_rate / RATE * ratio
            age = np.arange(count) / RATE
            if loop_end:
                loop_length = loop_end-loop_start-crossfade
                offsets -= np.maximum(0, np.floor((offsets-loop_end)/loop_length)+1) * loop_length
            tone = np.interp(offsets, np.arange(len(data)), data) * gain
            if loop_end:
                blend = np.clip((offsets-(loop_end-crossfade))/crossfade,0,1)
                alternate = np.interp(loop_start+offsets-(loop_end-crossfade),np.arange(len(data)),data) * gain
                tone = tone*(1-blend) + alternate*blend
                tone *= np.exp(-.12*np.maximum(0,age-loop_end/source_rate/ratio))
            fade_in = min(round(.004 * RATE), count)
            fade_out = min(round(.26 * RATE), count)
            tone[:fade_in] *= np.linspace(0, 1, fade_in)
            tone[-fade_out:] *= np.linspace(1, 0, fade_out)
            start = round(tick * RATE * seconds_per_tick)
            end = min(len(mix), start + count)
            mix[start:end] += tone[:end - start]
        peak = float(np.max(np.abs(mix)))
        assert peak > 0
        mix *= .62 / peak
        mix[-round(.18 * RATE):] *= np.linspace(1, 0, round(.18 * RATE))
        asset = f'assets/audio/backing_{slug.replace("-", "_")}_{tempo}.ogg'
        with sf.SoundFile(str(ROOT / asset), 'w', RATE, 1, format='OGG', subtype='VORBIS') as output:
            for begin in range(0, len(mix), 16384):
                output.write(mix[begin:begin+16384])
        variants[str(tempo)] = {
            'path': asset,
            'sha256': hashlib.sha256((ROOT / asset).read_bytes()).hexdigest(),
            'tempo_bpm': tempo,
            'duration_ms': round(total * 60000 / tempo / piece['ticks_per_beat']),
            'sample_frames': len(mix),
        }
    piece['accompaniment'] = {
        **variants['60'],
        'base_tempo_bpm': 60,
        'total_ticks': total,
        'variants': variants,
        'arrangement': 'Literal note events imported from individually selected accompaniment '
                       'score voices; see source adaptation and attribution.',
        'source': score['source'],
        'source_sha256': score['source_sha256'],
        'score_hash': score_hash,
        'score_note_count': len(events),
        'recording': 'Salamander Grand Piano V3, Alexander Holm, CC BY 3.0. '
                     'Local samples transposed, mixed, gated, resampled to mono 22050 Hz and '
                     'encoded as Ogg/Vorbis separately at each tempo; '
                     'see piano_attribution.txt.',
    }
    if score.get('voicing_adjustments'):
        piece['accompaniment']['source_note_count'] = score['source_note_count']
        piece['accompaniment']['voicing_adjustments'] = score['voicing_adjustments']
    piece['version'] = score['source'].get('content_version', '1.3.0')
    piece.pop('content_hash', None)
    canonical = json.dumps(piece, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    piece['content_hash'] = hashlib.sha256(canonical.encode()).hexdigest()
    path.write_text(json.dumps(piece, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(slug, 'five tempos,', len(events), 'accompaniment voices per track')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pieces', nargs='+', choices=SCORE_IDS, default=SCORE_IDS)
    parser.add_argument('--audit-version', default='0.1.39')
    args = parser.parse_args()
    from import_piece_backings import main as import_scores
    import_scores(args.audit_version)
    samples = read_samples()
    for slug in args.pieces:
        render(slug, samples)


if __name__ == '__main__':
    # The Windows Vorbis encoder needs more stack than Python's main thread.
    threading.stack_size(64 * 1024 * 1024)
    failures = []
    def run():
        try:
            main()
        except BaseException as error:
            failures.append(error)
    worker = threading.Thread(target=run)
    worker.start()
    worker.join()
    if failures:
        raise failures[0]
