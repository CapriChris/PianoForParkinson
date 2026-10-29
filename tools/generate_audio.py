"""Deterministic original development tones; no third-party recordings."""
import hashlib, json, math, pathlib, struct, wave
root = pathlib.Path(__file__).resolve().parents[1]
assets = []
for i, frequency in enumerate([261.6256, 293.6648, 329.6276, 349.2282, 391.9954, 440, 493.8833, 523.2511, 659.2551, 783.9909]):
    name = f'note_{i}' if i < 7 else f'prompt_{i-7}'
    path = root / 'assets' / 'audio' / f'{name}.wav'
    duration = 1.6 if i < 7 else .35
    samples = []
    for frame in range(round(44100 * duration)):
        t = frame / 44100
        envelope = min(1, t / .008) * math.exp(-3.5 * t) * min(1, (duration-t)/.05)
        value = sum(math.sin(2*math.pi*frequency*h*t) * math.exp(-.6*(h-1)) / h for h in range(1, 7))
        samples.append(struct.pack('<h', round(18000 * envelope * value / 1.8)))
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(44100); output.writeframes(b''.join(samples))
    assets.append(dict(asset_id=name, path=f'assets/audio/{name}.wav', sha256=hashlib.sha256(path.read_bytes()).hexdigest(), mime_type='audio/wav', duration_ms=round(duration*1000), license_id='PROJECT_ORIGINAL_DEVELOPMENT', source='tools/generate_audio.py: original additive synthesis', ready_status='DEVELOPMENT_ONLY'))
manifest = dict(version='sound-synth-demo-1.0.0', assets=assets)
(root/'assets'/'content'/'sound_pack.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
content = dict(content_id='song-original-001', version='1.0.0', category='ORIGINAL_EXERCISE', localized_title={'zh-Hans':'短旋律练习一','en':'Short Melody One'}, notes=[dict(note_index=n,duration_ms=400) for n in [0,1,2,4,2,1,0,0]], tempo_bpm=40, supported_tasks=['S1_GUIDED'], rights=dict(status='DEVELOPMENT_ONLY',melody='Original exercise sequence from DD-1.0',arrangement='Project original',recording='Original synthesized sounds; no samples or soundfonts'), assets=assets[:7])
encoded = json.dumps(content, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf8')
content['content_hash'] = hashlib.sha256(encoded).hexdigest()
(root/'assets'/'content'/'song.json').write_text(json.dumps(content, ensure_ascii=False, indent=2), encoding='utf8')
print('Generated 7 original key sounds, 3 prompts, and content manifests.')
