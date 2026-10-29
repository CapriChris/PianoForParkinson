"""Record the emulator's real audio/video using the isolated audit APK only.

No install, uninstall, clear-data or primary-app commands are issued here.
"""
import argparse
import json
import math
from pathlib import Path
import re
import shlex
import subprocess
import time

ADB = 'C:/Users/29564/AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE = 'com.pianoforparkinson.piano_practice.validation'
ROOT = Path(__file__).resolve().parents[1]
DURATIONS = {'ode-to-joy': 24, 'frere-jacques': 24, 'twinkle': 36,
             'saints': 48, 'happy-birthday': 18, 'you-are-my-sunshine': 48}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suffix', required=True)
    parser.add_argument('--pieces', nargs='+', choices=list(DURATIONS), default=list(DURATIONS))
    parser.add_argument('--tempo', type=int, choices=[40, 50, 60, 70, 80], default=80)
    args = parser.parse_args()
    assert re.fullmatch('[a-z0-9-]+', args.suffix)
    assert PACKAGE.endswith('.validation')
    out = ROOT / 'validation/audio-engine-0.1.39/recordings'
    out.mkdir(parents=True,exist_ok=True)

    def adb(*command):
        return subprocess.check_output([ADB, '-s', 'emulator-5554', *command],
                                       text=True, encoding='utf-8', errors='replace')

    for slug in args.pieces:
        piece=json.loads((ROOT/f'assets/content/piece-{slug}-001.json').read_text(encoding='utf8'))
        duration = math.ceil((sum(n['duration_ticks'] for n in piece['notes'])/piece['ticks_per_beat']+4)*60/args.tempo)
        adb('shell', 'am', 'force-stop', PACKAGE)
        video = out / f'{slug}-{args.suffix}.webm'
        adb('emu', 'screenrecord', 'start', '--size', '540x1200', '--fps', '24',
            '--bit-rate', '800000', '--time-limit', str(duration + 30),
            video.resolve().as_posix())
        route = f'/audit?piece={slug}&tempo={args.tempo}' + ('&mode=performance' if args.suffix.startswith('performance') else '')
        adb('shell', 'am start -n ' + PACKAGE + '/com.pianoforparkinson.piano_practice.MainActivity'
            + ' --es route ' + shlex.quote(route))
        deadline = time.monotonic() + duration + 35
        logs = ''
        while time.monotonic() < deadline:
            time.sleep(1)
            pid = adb('shell', 'pidof', PACKAGE).strip()
            logs = adb('logcat', '-d', '--pid=' + pid, '-s', 'flutter', 'QinAudio')
            if 'AUDIO_AUDIT_END ' in logs:
                break
        (out / f'{slug}-{args.suffix}.log').write_text(logs, encoding='utf-8')
        time.sleep(1)
        adb('emu', 'screenrecord', 'stop')
        assert 'AUDIO_AUDIT_END ' in logs, f'{slug}: audit did not complete'
        print(slug, next(line.split('AUDIO_AUDIT_END ', 1)[1]
                         for line in logs.splitlines() if 'AUDIO_AUDIT_END ' in line), flush=True)


if __name__ == '__main__':
    main()
