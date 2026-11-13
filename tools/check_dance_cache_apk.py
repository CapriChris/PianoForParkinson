"""Verify packaged dance metadata/media and optionally compare a baseline APK."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def inspect(apk: Path):
    root = Path(__file__).resolve().parents[1]
    remote = json.loads((root / 'assets/video/remote_manifest.json').read_text(encoding='utf-8'))
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate archive entries'
        packaged = json.loads(archive.read('assets/flutter_assets/assets/video/remote_manifest.json'))
        assert packaged == remote, 'Packaged metadata differs from source'
        for item in remote['items']:
            assert not any(Path(name).name == item['fileName'] for name in names), item['fileName']
        assert not any(name.endswith(('.mp4', '.webm')) for name in names), 'Teaching video remains bundled'
    with apk.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'apk': apk.name, 'bytes': apk.stat().st_size, 'sha256': digest,
            'remoteParts': len(remote['items']), 'remoteMp4Packaged': False,
            'teachingVideoPackaged': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = inspect(args.apk)
    if args.baseline:
        result['baselineBytes'] = args.baseline.stat().st_size
        result['reductionBytes'] = result['baselineBytes'] - result['bytes']
        result['reductionPercent'] = round(result['reductionBytes'] * 100 / result['baselineBytes'], 3)
    text = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(text + '\n', encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
