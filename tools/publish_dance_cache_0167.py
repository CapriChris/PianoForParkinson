"""Publish this immutable QA APK on fengz. Default is read-only preflight.

Run with the system Python as root, after uploading the verified APK to STAGE.
Never changes Nginx, systemd, databases, existing videos or Web source.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from urllib.request import urlopen

STAGE = Path('/opt/pd-rehab/releases/dance-cache-20261112-5488e9d')
ROOT = Path('/var/www/pd-rehab')
WEB = Path('/opt/pd-rehab/app/PD-Rehab-Web')
OLD_WEB_SHA = '90d5e53162f9e673c931334dabb885daef46b272'
SHA = '9253a5ecbba238777a5a12fac44c3e849909c1e9d03ae3481b7565612386a064'
SIZE = 469196327
NAME = 'PianoForParkinson-0.1.67-dance-cache-QA-arm64.apk'
BASE = ROOT / 'app-releases'
VERSION = BASE / '0.1.67'
LINKS = [ROOT / d / 'assets/app-releases' for d in ['dist', 'dist-under-path']]
UNITS = ['pd-rehab-backend', 'nginx', 'exercises', 'foodcircle-api',
         'his-18092-tls', 'llm-api-platform', 'smoking-monitor-api',
         'smoking-monitoring-system-api']


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def states():
    return {name: command('systemctl', 'show', name, '-p', 'ActiveState', '-p', 'MainPID')
            for name in UNITS}


def health():
    with urlopen('http://127.0.0.1:18086/api/system/health', timeout=20) as response:
        result = json.load(response)
        if result.get('status') != 'ok':
            raise RuntimeError('Backend not healthy')
    with urlopen('http://127.0.0.1:18086/api/system/models', timeout=20) as response:
        return json.load(response)['summary']


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    incoming = STAGE / 'app.apk.upload'
    require(command('git', '-C', str(WEB), 'rev-parse', 'HEAD') == OLD_WEB_SHA, 'Web SHA drift')
    require(not command('git', '-C', str(WEB), 'status', '--porcelain'), 'Web worktree dirty')
    require(incoming.is_file() and incoming.stat().st_size == SIZE, 'APK length mismatch')
    require(digest(incoming) == SHA, 'APK digest mismatch')
    require(not VERSION.exists() and not VERSION.is_symlink(), 'Version already exists')
    require(not BASE.is_symlink(), 'Public directory must not be a symlink')
    for link in LINKS:
        require(not link.exists() and not link.is_symlink(), 'Unknown download mapping')
        require(link.parent.is_dir() and not link.parent.is_symlink(), 'Unexpected assets directory')
    before, models_before = states(), health()
    if '--publish' not in sys.argv:
        print(json.dumps({'preflight': 'passed', 'bytes': SIZE, 'sha256': SHA,
                          'models': models_before, 'services': before}))
        return
    require(os.geteuid() == 0, 'Run publication as root')
    require(STAGE.stat().st_dev == ROOT.stat().st_dev, 'Atomic move requires same filesystem')
    BASE.mkdir(mode=0o755, exist_ok=True)
    VERSION.mkdir(mode=0o755)
    target = VERSION / NAME
    os.replace(incoming, target)
    os.chown(target, 0, 0)
    target.chmod(0o644)
    require(digest(target) == SHA, 'Installed APK digest mismatch')
    (VERSION / 'SHA256SUMS.txt').write_text(f'{SHA}  {NAME}\n', encoding='utf-8')
    metadata = {'version': '0.1.67+68', 'sourceCommit': '5488e9d',
                'kind': 'isolated-arm64-debug-QA',
                'applicationId': 'com.pianoforparkinson.piano_practice.validation',
                'apk': NAME, 'bytes': SIZE, 'sha256': SHA,
                'physicalDeviceValidation': 'not-performed-no-device',
                'flutterTests': {'passed': 814, 'skipped': 2},
                'nativeTests': {'passed': 104, 'skipped': 0}}
    (VERSION / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    for file in VERSION.iterdir():
        file.chmod(0o644)
    for link in LINKS:
        link.symlink_to(BASE, target_is_directory=True)
    after, models_after = states(), health()
    require(after == before, 'Service state/PID drift: inspect before reporting deployment')
    require(models_after['ready'] == models_before['ready'] == 4, 'Model readiness changed')
    require(command('git', '-C', str(WEB), 'rev-parse', 'HEAD') == OLD_WEB_SHA, 'Web SHA changed')
    result = {'published': metadata, 'servicesBefore': before, 'servicesAfter': after,
              'modelsBefore': models_before, 'modelsAfter': models_after,
              'webShaUnchanged': OLD_WEB_SHA, 'restartedServices': []}
    (STAGE / 'deployment-result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
