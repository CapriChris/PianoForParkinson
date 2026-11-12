"""Restore exact bundled playback assets from originals or a release APK.

Only bundled manifest-listed files are required; originals are never modified.
Use --include-remote to restore the three online MP4 originals for local archives.
No third-party Python dependencies or video transcoding are required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import zipfile


def matches(path, asset):
    if not path.is_file() or path.stat().st_size != asset['bytes']:
        return False
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() == asset['sha256']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-apk', type=Path, help='Extract videos from a downloaded Qinban release APK.')
    parser.add_argument('--check', action='store_true', help='Only verify existing playback assets.')
    parser.add_argument('--include-remote', action='store_true', help='Also restore/check originals now served remotely; not needed to build.')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'assets' / 'video'
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    packaged = (root.parents[1] / 'pubspec.yaml').read_text(encoding='utf-8')
    bundled = {line.strip()[2:] for line in packaged.splitlines() if line.strip().startswith('- assets/video/')}
    archive = zipfile.ZipFile(args.from_apk) if args.from_apk else None
    try:
        for asset in manifest['assets']:
            name = asset['name']
            if Path(name).name != name or '/' in name or '\\' in name:
                raise ValueError('Manifest filenames must not contain directories')
            if not args.include_remote and f'assets/video/{name}' not in bundled:
                continue
            target = root / name
            if target.exists():
                if not matches(target, asset):
                    raise RuntimeError(f'Existing asset differs: {name}. Preserve or move it before restoring.')
            elif args.check:
                raise FileNotFoundError(f'Missing playback asset: {name}')
            else:
                temporary = root / f'{name}.prepare-{os.getpid()}.partial'
                try:
                    if archive:
                        source = archive.open(f'assets/flutter_assets/assets/video/{name}')
                    else:
                        original = asset.get('source_name')
                        if original:
                            source_path = root / original
                        else:
                            candidates = list(root.glob('Bora_*.webm'))
                            if len(candidates) != 1:
                                raise FileNotFoundError('Provide the original Bora_*.webm or use --from-apk.')
                            source_path = candidates[0]
                        source = source_path.open('rb')
                    with source, temporary.open('xb') as destination:
                        shutil.copyfileobj(source, destination, length=1024 * 1024)
                    if not matches(temporary, asset):
                        raise RuntimeError(f'Asset hash/size mismatch: {name}')
                    temporary.replace(target)
                finally:
                    if temporary.exists():
                        temporary.unlink()
            print(f'Verified: {name}; SHA-256 {asset["sha256"]}', flush=True)
    finally:
        if archive:
            archive.close()


if __name__ == '__main__':
    main()
