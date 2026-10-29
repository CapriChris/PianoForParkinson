"""Build offline piano assets. pip install --target tools/.audio_deps numpy scipy soundfile."""
import hashlib, json, math, pathlib, sys, urllib.parse, urllib.request
sys.path.insert(0, str(pathlib.Path(__file__).parent / '.audio_deps'))
import numpy as np
import scipy.signal as signal
import soundfile as sf

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = ROOT / 'tools' / 'audio_sources'
CACHE.mkdir(exist_ok=True)
REVISION = sys.argv[1] if len(sys.argv) > 1 else json.loads((CACHE / 'sources.json').read_text())['revision']
BASE = f'https://raw.githubusercontent.com/sfzinstruments/SalamanderGrandPiano/{REVISION}'
SOURCE = 'https://github.com/sfzinstruments/SalamanderGrandPiano'
sources = {}
def fetch(name, relative):
    path = CACHE / name
    url = BASE + '/' + urllib.parse.quote(relative, safe='/')
    if not path.exists():
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'PianoPractice-assets'}), timeout=90) as response:
            path.write_bytes(response.read())
    sources[name] = {'url': url, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    return path

samples = {}
for name, midi in [('C4',60), ('D#4',63), ('F#4',66), ('A4',69), ('C5',72)]:
    data, rate = sf.read(fetch(name+'v8.flac', 'Samples/'+name+'v8.flac'), always_2d=True)
    samples[midi] = (data.mean(axis=1), rate, name+'v8.flac')
license_text = fetch('LICENSE', 'LICENSE').read_text(encoding='utf8')
old = json.loads((ROOT/'assets/content/sound_pack.json').read_text(encoding='utf8'))
assets = []
prepared = []
for i, midi in enumerate([60,62,64,65,67,69,71]):
    nearest = min(samples, key=lambda k: abs(k-midi))
    data, rate, source = samples[nearest]
    # Polyphase filtering supplies antialiasing before transposition/resampling.
    target_rate = round(44100 / (2 ** ((midi-nearest)/12)))
    divisor = math.gcd(target_rate, rate)
    out = signal.resample_poly(data, target_rate//divisor, rate//divisor)[:132300]
    out = np.pad(out, (0, max(0,132300-len(out))))
    out[-2205:] *= np.linspace(1,0,2205)
    prepared.append((out, source, midi-nearest))
scale = .84 / max(float(np.max(np.abs(p[0]))) for p in prepared)
for i,(data,source,transpose) in enumerate(prepared):
    path = ROOT/f'assets/audio/note_{i}.wav'
    sf.write(path, data*scale, 44100, subtype='PCM_16')
    assets.append(dict(asset_id=f'note_{i}', path=f'assets/audio/note_{i}.wav',
        sha256=hashlib.sha256(path.read_bytes()).hexdigest(), mime_type='audio/wav', duration_ms=3000,
        license_id='CC-BY-3.0', author='Alexander Holm', title='Salamander Grand Piano V3',
        source=sources[source]['url'], source_sha256=sources[source]['sha256'],
        modifications=f'Velocity 8; mono downmix; transpose {transpose:+d} semitones; 44.1kHz PCM16; 3s crop; final 50ms fade; common gain normalization',
        ready_status='DEVELOPMENT_ONLY'))
# A dry, soft wooden metronome click, distinct from the piano notes.
t = np.arange(3969)/44100
click = .48*np.sin(2*np.pi*1450*t)*np.exp(-95*t) + .16*np.sin(2*np.pi*2900*t)*np.exp(-160*t)
click[:90] *= np.linspace(0,1,90)
sf.write(ROOT/'assets/audio/prompt_0.wav', click, 44100, subtype='PCM_16')
for i in range(3):
    item = next(a for a in old['assets'] if a['asset_id']==f'prompt_{i}')
    if i == 0:
        item.update(duration_ms=90, sha256=hashlib.sha256((ROOT/'assets/audio/prompt_0.wav').read_bytes()).hexdigest(), source='tools/build_sampled_piano.py: original metronome click')
    assets.append(item)
manifest = dict(version='sound-salamander-demo-1.0.0', assets=assets)
(ROOT/'assets/content/sound_pack.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
attribution = ('Salamander Grand Piano V3\nAuthor: Alexander Holm\n'+SOURCE+'\n'
    'License: Creative Commons Attribution 3.0 Unported (CC BY 3.0)\nhttps://creativecommons.org/licenses/by/3.0/\n'
    'Adapted for Piano Practice Companion: velocity layer 8, mono downmix, nearby-note transposition, resampling to 44.1kHz PCM16, 3-second excerpt, end fade, common gain normalization.\n'
    'Original recordings and attribution are retained; no endorsement by the author is implied.\n\n'+license_text)
(ROOT/'assets/content/piano_attribution.txt').write_text(attribution,encoding='utf8')
(CACHE/'sources.json').write_text(json.dumps(dict(revision=REVISION,sources=sources),indent=2)+'\n',encoding='utf8')
song = json.loads((ROOT/'assets/content/song.json').read_text(encoding='utf8'))
song.pop('content_hash',None)
song.update(version='2.0.0', assets=assets[:7])
song['rights']['recording'] = 'Salamander Grand Piano V3, Alexander Holm, CC BY 3.0; adaptations credited in piano_attribution.txt'
song['content_hash'] = hashlib.sha256(json.dumps(song,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
(ROOT/'assets/content/song.json').write_text(json.dumps(song,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('Built 7 sampled piano notes, metronome, hashes and bundled attribution; revision',REVISION)
