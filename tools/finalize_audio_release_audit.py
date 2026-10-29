"""Verify delivery bytes against the audited engine/assets and write the report."""
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]
AUDIT=ROOT/'validation/audio-engine-0.1.39'
RELEASE=ROOT.parent/'releases/琴伴-0.1.39-internal.apk'
ISOLATED=AUDIT/'isolated-native-final.apk'
SLUGS=['ode-to-joy','frere-jacques','twinkle','saints','happy-birthday','you-are-my-sunshine']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    evidence=json.loads((AUDIT/'objective-audio-report.json').read_text(encoding='utf8'))
    runs=evidence['final_recordings']
    assert len(runs)==8, len(runs)
    assert {r['piece'] for r in runs if r['premixed_preview'] and r['tempo']==80}==set(SLUGS)
    assert any(r['tempo']==40 and r['piece']=='saints' for r in runs)
    assert any(r['record_saved'] and r['pause_resume_checked'] and not r['premixed_preview'] for r in runs)
    assert 'No issues found!' in (AUDIT/'analyze-final.log').read_text(encoding='utf8')
    testlog=(AUDIT/'delivery-tests.log').read_text(encoding='utf8')
    count=int(re.findall(r'\+(\d+): All tests passed!',testlog)[-1])
    assert count==86
    bank=json.loads((ROOT/'assets/content/piano_bank.json').read_text(encoding='utf8'))
    assets=[e['path'] for e in bank['samples']]
    pack=json.loads((ROOT/'assets/content/sound_pack.json').read_text(encoding='utf8'))
    assets.extend(e['path'] for e in pack['assets'])
    assets += ['assets/content/piano_bank.json','assets/content/sound_pack.json',
               'assets/content/piano_attribution.txt','assets/content/backing_score_attribution.txt',
               'assets/content/oboe_license.txt','assets/content/stb_license.txt']
    pieces=[]
    for slug in SLUGS:
        path=f'assets/content/piece-{slug}-001.json'
        p=json.loads((ROOT/path).read_text(encoding='utf8'))
        assets.append(path)
        variants=p['accompaniment']['variants']
        assert len(variants)==5
        assets.extend(v['path'] for v in variants.values())
        pieces.append(dict(id=p['content_id'],content_hash=p['content_hash'],
                           ticks=p['accompaniment']['total_ticks'],ticks_per_beat=p['ticks_per_beat'],
                           score_hash=p['accompaniment']['score_hash']))
    comparisons=[]
    with zipfile.ZipFile(RELEASE) as production, zipfile.ZipFile(ISOLATED) as isolated:
        for path in assets:
            data=(ROOT/path).read_bytes()
            member='assets/flutter_assets/'+path
            assert production.read(member)==data, path
            assert isolated.read(member)==data, path
        for abi in ['arm64-v8a','armeabi-v7a','x86_64']:
            member=f'lib/{abi}/libqin_audio.so'
            assert production.read(member)==isolated.read(member), abi
            comparisons.append(dict(abi=abi,sha256=sha(production.read(member))))
    third=ROOT/'android/app/src/main/cpp/third_party'
    source=json.loads((third/'source.json').read_text())
    for name,item in source['files'].items():
        assert sha((third/name).read_bytes())==item['sha256']
    assert 'PASS:' in (AUDIT/'native-mixer-test.log').read_text(encoding='utf8')
    report=dict(version='0.1.39',build=40,package='com.pianoforparkinson.piano_practice',
                release=str(RELEASE.resolve()),bytes=RELEASE.stat().st_size,
                sha256=sha(RELEASE.read_bytes()).upper(),
                release_build_passed=True,host_tests_passed=count,static_analysis='No issues found',
                full_test_suite_run=False,native_mixer_tests_passed=True,
                engine='Oboe 1.11.0 single output stream',decoder='stb_vorbis 1.22',
                decoder_revision=source['revision'],piano_bank_samples=17,
                verified_tempo_tracks=30,verified_delivery_assets=len(assets),
                identical_native_binaries=comparisons,pieces=pieces,
                emulator_final_runs=runs,human_listening_performed=False,audio_input_supported=False,
                emulator_snapshot='qin-before-engine-20261026',
                isolated_package='com.pianoforparkinson.piano_practice.validation',
                primary_app_installed_or_cleared=False,primary_private_db_row_audit=False)
    if (AUDIT/'primary-package-after.txt').exists():
        report['primary_package_after']=(AUDIT/'primary-package-after.txt').read_text(encoding='utf8')
    (ROOT.parent/'releases/build-report-0.1.39.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('Verified',len(assets),'assets, three native ABIs,',len(runs),'final simulator runs and',count,'host tests')
    print(report['bytes'],report['sha256'])


if __name__=='__main__':
    main()
