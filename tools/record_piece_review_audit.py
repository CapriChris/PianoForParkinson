"""Native input-replay audit. Never installs or clears the primary application."""
from pathlib import Path
import json,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'validation/piece-review-0.1.44'
ADB='C:/Users/29564/AppData/Local/Android/Sdk/platform-tools/adb.exe'
PACKAGE='com.pianoforparkinson.piano_practice.validation'
def adb(*args,binary=False):
    result=subprocess.check_output([ADB,'-s','emulator-5554',*args],timeout=25)
    return result if binary else result.decode('utf8',errors='replace')
def main():
    results=[]
    for mode in ['score','replay','transport','legacy','audition']:
        adb('shell','am','force-stop',PACKAGE)
        video=(OUT/f'{mode}.webm').resolve().as_posix()
        adb('emu','screenrecord','start','--size','540x1200','--fps','24','--bit-rate','1600000','--time-limit','35',video)
        captured=False;log='';ready=None;end=None
        try:
            adb('shell','am','start','-n',PACKAGE+'/com.pianoforparkinson.piano_practice.MainActivity','--es','route','/review?mode='+mode)
            deadline=time.monotonic()+32
            while time.monotonic()<deadline:
                time.sleep(.25)
                try:pid=adb('shell','pidof',PACKAGE).strip()
                except subprocess.CalledProcessError:continue
                log=adb('logcat','-d','--pid='+pid,'-s','flutter','QinAudio')
                match=re.search(r'REVIEW_AUDIT_READY (\{[^\r\n]+\})',log)
                if match and not captured:
                    ready=json.loads(match[1]);captured=True
                    (OUT/f'{mode}.png').write_bytes(adb('exec-out','screencap','-p',binary=True))
                match=re.search(r'REVIEW_AUDIT_END (\{[^\r\n]+\})',log)
                if match:end=json.loads(match[1]);break
                if 'Unhandled Exception' in log or 'EXCEPTION CAUGHT' in log:break
            (OUT/f'{mode}.log').write_text(log,encoding='utf8')
            assert ready and end,f'{mode}: native audit failed; inspect log'
            result={'ready':ready,'end':end}
            results.append(result);print(result,flush=True)
        finally:adb('emu','screenrecord','stop')
    (OUT/'emulator-results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf8')
if __name__=='__main__':main()
