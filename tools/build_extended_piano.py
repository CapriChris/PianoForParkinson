"""Build the native sampler's C2-C6 bank from pinned Salamander recordings.

Legacy note/prompt assets stay intact for content/history compatibility. The
new bank retains the entire natural tail, and supplies a crossfaded sustain
region used only after the initial four seconds of a held key.
"""
import hashlib
import json
from pathlib import Path
import sys
import urllib.parse
import urllib.request
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tmp/audio-tooling'))
import soundfile as sf

REVISION = '3382bf9496bba2486f5ab0de55a264d1dfc38404'
RATE = 24000
CACHE = ROOT / 'tools/audio_sources'


def resample(data, rate):
    if rate == RATE:
        return data
    # Low-pass before downsampling; no scipy dependency is needed by this tool.
    cutoff = .47 * min(1, RATE / rate)
    n = np.arange(-96, 97)
    kernel = 2 * cutoff * np.sinc(2 * cutoff * n) * np.hamming(len(n))
    kernel /= kernel.sum()
    filtered = np.convolve(data, kernel, mode='same')
    return np.interp(np.arange(round(len(data) * RATE / rate)) * rate / RATE,
                     np.arange(len(data)), filtered)


def main():
    prepared = []
    names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    for midi in range(36, 85, 3):
        name = f'{names[midi % 12]}{midi // 12 - 1}v8.flac'
        path = CACHE / name
        url = f'https://raw.githubusercontent.com/sfzinstruments/SalamanderGrandPiano/{REVISION}/Samples/' + urllib.parse.quote(name)
        if not path.exists():
            with urllib.request.urlopen(url, timeout=90) as response:
                path.write_bytes(response.read())
        data, rate = sf.read(path, always_2d=True)
        data = resample(data.mean(axis=1), rate)
        assert len(data) > 5 * RATE
        prepared.append((midi, name, url, data))
        print(name, round(len(data) / RATE, 2), 'seconds', flush=True)
    scale = .72 / max(np.max(np.abs(data)) for _, _, _, data in prepared)
    entries = []
    for midi, name, url, data in prepared:
        asset = f'assets/audio/piano_{midi}.wav'
        data = data * scale
        data[:96] *= np.linspace(0, 1, 96)
        data[-1200:] *= np.linspace(1, 0, 1200)
        sf.write(ROOT / asset, data, RATE, subtype='PCM_16')
        # Integer cycles and an 85 ms overlap prevent a hard splice. The
        # sampler continues a slow decay across loops rather than reattacking.
        period = RATE / (440 * 2 ** ((midi - 69) / 12))
        loop_start = round(2.5 * RATE)
        loop_end = loop_start + round(round(2 * RATE / period) * period)
        entries.append(dict(midi=midi, path=asset,
            sha256=hashlib.sha256((ROOT / asset).read_bytes()).hexdigest(),
            sample_rate=RATE, sample_frames=len(data),
            loop_start=loop_start, loop_end=loop_end, crossfade_frames=2048,
            source=url, source_sha256=hashlib.sha256((CACHE / name).read_bytes()).hexdigest()))
    manifest = dict(version='salamander-extended-1.0.0', sample_rate=RATE,
                    release_ms=260, author='Alexander Holm', license='CC-BY-3.0',
                    source_revision=REVISION, samples=entries)
    (ROOT / 'assets/content/piano_bank.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    pack_path = ROOT / 'assets/content/sound_pack.json'
    pack = json.loads(pack_path.read_text(encoding='utf8'))
    pack['piano_bank'] = 'assets/content/piano_bank.json'
    pack['version'] = 'sound-salamander-extended-2.0.0'
    pack_path.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    attribution_path = ROOT / 'assets/content/piano_attribution.txt'
    attribution = attribution_path.read_text(encoding='utf8')
    marker = '\nExtended native sampler bank (2026-10-26):'
    attribution = attribution.split(marker)[0]
    attribution_path.write_text(attribution + marker + '\n'
        '17 recordings, C2-C6 at minor-third intervals, velocity layer 8; entire natural tails; '
        'mono downmix, anti-aliased resampling to 24 kHz PCM16, common gain and edge fades. '
        'Nearby pitches are interpolated by the sampler; held notes use a crossfaded, slowly '
        'decaying sustain region with a 260 ms key-release envelope. '
        'Source: Alexander Holm, Salamander Grand Piano V3, CC BY 3.0.\n', encoding='utf8')


if __name__ == '__main__':
    main()
