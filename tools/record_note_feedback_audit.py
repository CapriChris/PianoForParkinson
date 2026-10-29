"""Capture only the isolated visual audit app; never clear or install the main app."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'validation/note-feedback-0.1.40'
ADB='C:/Users/29564/AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE='com.pianoforparkinson.piano_practice.validation'


def adb(*args):
    return subprocess.check_output([ADB,'-s','emulator-5554',*args],text=True,encoding='utf8',errors='replace')


def main():
    assert PACKAGE.endswith('.validation')
    results=[]
    for mode in ['preview','performance','other']:
        adb('shell','am','force-stop',PACKAGE)
        video=OUT/f'{mode}.webm'
        size='540x1200'
        adb('emu','screenrecord','start','--size',size,'--fps','30','--bit-rate','2500000',
            '--time-limit','24',video.resolve().as_posix())
        try:
            route=f'/feedback?mode={mode}'
            adb('shell','am start -n '+PACKAGE+'/com.pianoforparkinson.piano_practice.MainActivity --es route '+shlex.quote(route))
            deadline=time.monotonic()+24
            log=''
            while time.monotonic()<deadline:
                time.sleep(.5)
                pid=adb('shell','pidof',PACKAGE).strip()
                log=adb('logcat','-d','--pid='+pid,'-s','flutter')
                if 'FEEDBACK_AUDIT_END ' in log:
                    break
            (OUT/f'{mode}.log').write_text(log,encoding='utf8')
            match=re.search(r'FEEDBACK_AUDIT_END (\{[^\r\n]*\})',log)
            assert match, f'{mode}: visual audit did not finish'
            result=json.loads(match[1])
            press=re.search(r'FEEDBACK_AUDIT_PRESS (\{[^\r\n]*\})',log)
            if press:
                result['press']=json.loads(press[1])
            results.append(result)
            print(result,flush=True)
        finally:
            adb('emu','screenrecord','stop')
    (OUT/'emulator-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf8')


if __name__=='__main__':
    main()
