"""Decode actual emulator captures; report objective checks, never listening."""
import json
from pathlib import Path
import re
import numpy as np
from analyze_piece_audio_audit import convert_audio, RATE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'validation/audio-engine-0.1.39'


def main():
    results=[]
    for path in sorted((OUT/'recordings').glob('*.log')):
        log=path.read_text(encoding='utf8')
        endings=re.findall(r'AUDIO_AUDIT_END (\{[^\r\n]*\})',log)
        assert endings, path.name
        result=json.loads(endings[-1])
        result['final_native_decoder_run'] = path.stem.endswith(('-native-decoder','-native-slow','-performance-native'))
        result['preparations'] = [dict(path=p,decode_ms=int(d),premix_ms=int(m))
                                  for p,d,m in re.findall(r'prepare (\S+) decode_ms=(\d+) premix_ms=(\d+)',log)]
        assert result['mode']=='complete'
        assert result['elapsed_us']==result['expected_us']
        assert result['backing_observed_playing']
        assert result['audio_state']['engine']=='OBOE'
        assert result['audio_state']['active_voice_count']==0
        assert not result['audio_state']['piece_backing_playing']
        if result['pause_resume_checked']:
            assert result['record_saved']
        data=convert_audio(path.with_suffix('.webm'))
        assert np.isfinite(data).all()
        result.update(recording=path.with_suffix('.webm').name,
                      audio_peak=float(np.max(np.abs(data))),
                      captured_audio_seconds=len(data)/RATE)
        assert result['audio_peak']<.999
        if 'AUDIO_SUSTAIN_PROBE' in log:
            probe=json.loads(re.search(r'AUDIO_SUSTAIN_PROBE (\{[^\r\n]*\})',log)[1])
            assert probe['held_after_8s']['active_voice_count']==1
            assert probe['released']['active_voice_count']==0
            blocks=data[:len(data)//1600*1600].reshape(-1,1600)
            rms=np.sqrt(np.mean(blocks**2,axis=1))
            start=int(np.flatnonzero(rms>.003)[0])*1600
            tail=data[start+5*RATE:start+int(7.5*RATE)]
            result['sustain_5_to_7_5s_rms']=float(np.sqrt(np.mean(tail**2)))
            assert result['sustain_5_to_7_5s_rms']>.001
            excerpt=data[start+RATE//4:start+RATE*5//4]
            spectrum=np.abs(np.fft.rfft(excerpt*np.hanning(len(excerpt))))
            freq=np.fft.rfftfreq(len(excerpt),1/RATE)
            mask=(freq>250)&(freq<275)
            f=float(freq[mask][np.argmax(spectrum[mask])])
            result['probe_C4_peak_hz']=f
            assert abs(f-261.626)<2
        results.append(result)
        print(path.stem,'complete; peak',round(result['audio_peak'],3),
              'clock p95(us)',result['clock_error_p95_us'],'underruns',result['max_underruns'],flush=True)
    report=dict(human_listening_performed=False, audio_input_supported=False,
                clock_error_is_not_touch_to_speaker_latency=True,
                final_recordings=[r for r in results if r['final_native_decoder_run']],
                recordings=results)
    (OUT/'objective-audio-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')


if __name__=='__main__':
    main()
