"""Capture synthetic metric examples only in the isolated package."""
from pathlib import Path
import json,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'validation/metric-ui-0.1.43'
ADB='C:/Users/29564/AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE='com.pianoforparkinson.piano_practice.validation'

def adb(*args,binary=False):
    data=subprocess.check_output([ADB,'-s','emulator-5554',*args])
    return data if binary else data.decode('utf8',errors='replace')

def main():
    assert PACKAGE.endswith('.validation')
    results=[]
    for mode in ['result','details','timing','piece','history','trend']:
        adb('shell','am','force-stop',PACKAGE)
        adb('shell','am','start','-n',PACKAGE+'/com.pianoforparkinson.piano_practice.MainActivity','--es','route','/metrics?mode='+mode)
        deadline=time.monotonic()+18
        ready=None
        while time.monotonic()<deadline:
            time.sleep(.4)
            pid=adb('shell','pidof',PACKAGE).strip()
            log=adb('logcat','-d','--pid='+pid,'-s','flutter')
            match=re.search(r'METRIC_UI_READY (\{[^\r\n]+\})',log)
            if match:
                ready=json.loads(match[1]);break
        (OUT/f'{mode}.log').write_text(log,encoding='utf8')
        assert ready is not None, f'{mode}: no ready signal; inspect log'
        assert 'Unhandled Exception' not in log and 'EXCEPTION CAUGHT' not in log,log
        time.sleep(.3)
        (OUT/f'{mode}.png').write_bytes(adb('exec-out','screencap','-p',binary=True))
        results.append(ready)
        print(ready,flush=True)
    (OUT/'emulator-results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf8')

if __name__=='__main__':
    main()
