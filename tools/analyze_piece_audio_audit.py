"""Objective emulator recording checks; never described as human listening.

Compare real audio with the exact backing asset and a synthesized melody timing
template. Report timing separately from musical interpretation of chord tones.
"""
import argparse
import io
import json
import math
from pathlib import Path
import re
import sys
import wave
import zipfile

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tmp/audio-tooling'))
sys.path.insert(0, str(ROOT / 'validation/.video_deps'))
import soundfile as sf
import av

RATE = 16000
SAMPLE_MIDI = [60, 62, 64, 65, 67, 69, 71]
STEP_MIDI = [55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72]


def records(log, tag):
    return [json.loads(s) for s in re.findall('AUDIO_AUDIT_' + tag + r' (\{[^\r\n]*\})', log)]


def convert_audio(path):
    resampler = av.AudioResampler(format='s16', layout='mono', rate=RATE)
    chunks = []
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(frame))
        chunks.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(None))
    data = np.concatenate(chunks).astype(np.float64) / 32768
    with wave.open(str(path.with_suffix('.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, len(data), 'NONE', 'not compressed'))
        w.writeframes((data * 32768).astype('<i2').tobytes())
    return data


def band(data, low, high):
    spectrum = np.fft.rfft(data)
    frequencies = np.fft.rfftfreq(len(data), 1 / RATE)
    spectrum[(frequencies < low) | (frequencies > high)] = 0
    return np.fft.irfft(spectrum, len(data))


def onset(data, low, high):
    filtered = band(data, low, high)
    width = round(.015 * RATE)
    power = np.cumsum(np.r_[0, filtered * filtered])
    energy = np.sqrt(np.maximum(0, (power[width:] - power[:-width]) / width))
    energy = np.pad(energy, (width // 2, width - 1 - width // 2))
    delay = round(.02 * RATE)
    return np.maximum(0, energy - np.r_[np.zeros(delay), energy[:-delay]])


def correlation_lag(recording, template, limits=None):
    size = 1 << (len(recording) + len(template) - 2).bit_length()
    corr = np.fft.irfft(np.fft.rfft(recording, size) * np.conj(np.fft.rfft(template, size)), size)
    lo, hi = 0, len(recording) - len(template)
    if limits is not None:
        lo = max(lo, round(limits[0] * RATE))
        hi = min(hi, round(limits[1] * RATE))
    assert hi > lo
    lag = lo + int(np.argmax(corr[lo:hi + 1]))
    coefficient = corr[lag] / max(1e-12, np.linalg.norm(template) * np.linalg.norm(recording[lag:lag + len(template)]))
    return lag / RATE, float(coefficient)


def melody(piece, tempo, archive):
    total = round(sum(n['duration_ticks'] for n in piece['notes']) * 30 / tempo * RATE)
    result = np.zeros(total)
    notes = []
    tick = 0
    for note in piece['notes']:
        if note['note_index'] >= 0:
            step = piece.get('key_steps', [0, 1, 2, 3, 4])[note['note_index']]
            midi = STEP_MIDI[step + 3]
            index = min(range(7), key=lambda i: abs(midi - SAMPLE_MIDI[i]))
            speed = round(2 ** ((midi - SAMPLE_MIDI[index]) / 12) * 1000) / 1000
            data, rate = sf.read(io.BytesIO(archive.read(f'assets/flutter_assets/assets/audio/note_{index}.wav')))
            length = min(round((note['duration_ticks'] * 30 / tempo + .08) * RATE),
                         int(len(data) * RATE / rate / speed))
            tone = np.interp(np.arange(length) * rate / RATE * speed, np.arange(len(data)), data)
            release = min(round(.08 * RATE), length)
            tone[-release:] *= np.linspace(1, 0, release)
            start = round(tick * 30 / tempo * RATE)
            end = min(total, start + length)
            result[start:end] += tone[:end - start]
            notes.append({'tick': tick, 'midi': midi, 'sample': index, 'speed': speed})
        tick += note['duration_ticks']
    return result, notes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suffix', required=True)
    parser.add_argument('--apk', default=str(ROOT.parent / 'releases/琴伴-0.1.37-internal.apk'))
    parser.add_argument('--pieces', nargs='*')
    args = parser.parse_args()
    folder = ROOT / 'validation/audio-audit-0.1.37'
    archive = zipfile.ZipFile(args.apk)
    paths = sorted(folder.glob(f'*-{args.suffix}.webm'))
    reports = []
    for path in paths:
        slug = path.stem.removesuffix('-' + args.suffix)
        if args.pieces and slug not in args.pieces:
            continue
        log = path.with_suffix('.log').read_text(encoding='utf-8-sig')
        end = records(log, 'END')[-1]
        tempo = end['tempo']
        piece = json.loads(archive.read(f'assets/flutter_assets/assets/content/piece-{slug}-001.json'))
        recording = convert_audio(path)
        predicted, expected = melody(piece, tempo, archive)
        down = [n for n in records(log, 'NOTE') if n['down']]
        assert len(down) == len(expected), (slug, len(down), len(expected))
        deltas = [(actual['requested_us'] - down[0]['requested_us']) -
                  round((note['tick'] - expected[0]['tick']) * 30000000 / tempo)
                  for note, actual in zip(expected, down)]
        assert all(abs(SAMPLE_MIDI[d['sample']] + 12 * math.log2(d['rate_permille'] / 1000) - n['midi']) < .03
                   for n, d in zip(expected, down))
        # Mid/high melody partials dominate the tune; bass isolates the backing.
        melody_lag, melody_match = correlation_lag(band(recording, 250, 2500), band(predicted, 250, 2500))
        variant = piece['accompaniment']['variants'][str(tempo)]
        backing, sr = sf.read(io.BytesIO(archive.read('assets/flutter_assets/' + variant['path'])))
        backing = np.interp(np.arange(round(len(backing) * RATE / sr)) * sr / RATE,
                            np.arange(len(backing)), backing)
        low_y, low_x = band(recording, 70, 240), band(backing, 70, 240)
        backing_lag, backing_match = correlation_lag(low_y, low_x, (melody_lag - .3, melody_lag + .3))
        melody_onset, mc = correlation_lag(onset(recording, 250, 3000), onset(predicted, 250, 3000))
        backing_onset, bc = correlation_lag(onset(recording, 70, 240), onset(backing, 70, 240),
                                            (melody_onset - .3, melody_onset + .3))
        duration = len(backing) / RATE
        lag_windows = []
        for start in [1, max(1, duration / 2 - 3), max(1, duration - 7)]:
            sample_start = round(start * RATE)
            sample_end = min(len(backing), sample_start + 6 * RATE)
            lag, match = correlation_lag(low_y, low_x[sample_start:sample_end],
                                         (backing_lag + start - .08, backing_lag + start + .08))
            lag_windows.append({'at_seconds': start, 'backing_origin_seconds': lag - start, 'correlation': match})
        row = {'piece': slug, 'tempo': tempo, 'complete': end['mode'] == 'complete',
               'backing_observed_playing': end['backing_observed_playing'],
               'melody_notes_observed': len(down),
               'request_timing_range_ms': [min(deltas) / 1000, max(deltas) / 1000],
               'recorded_audio_seconds': len(recording) / RATE,
               'recorded_peak': float(max(abs(recording))),
               'melody_template_origin_seconds': melody_lag, 'melody_correlation': melody_match,
               'backing_template_origin_seconds': backing_lag, 'backing_correlation': backing_match,
               'waveform_correlation_delta_hint_ms': (backing_lag - melody_lag) * 1000,
               'phase_template_estimates_are_not_absolute_latency_measurements': True,
               'onset_alignment_hint': {
                   'melody_origin_seconds': melody_onset, 'melody_correlation': mc,
                   'backing_origin_seconds': backing_onset, 'backing_correlation': bc,
                   'difference_ms': (backing_onset - melody_onset) * 1000,
                   'interpretation': 'Approximate mixed-recording comparison, not a calibrated latency bound; '
                                     'low correlations remain inconclusive.'},
               'backing_window_alignment': lag_windows,
               'not_human_listening': True}
        reports.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
    (folder / f'objective-{args.suffix}.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
