#include "piano_mixer.h"
#include <oboe/Oboe.h>
#include <jni.h>
#include <atomic>
#include <memory>
#include <time.h>
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "third_party/stb_vorbis.c"

namespace {
struct Command { int kind=0, id=0, note=0; float ratio=1, gain=0; int64_t position=0; };
class Engine : public oboe::AudioStreamDataCallback, public oboe::AudioStreamErrorCallback {
public:
    qin::Mixer mixer;
    std::shared_ptr<oboe::AudioStream> stream;
    std::vector<float> track;
    int trackRate=22050;
    float trackGain=0;
    std::array<Command,256> queue;
    std::atomic<unsigned> read{0}, write{0};
    std::atomic<int> active{0};
    std::atomic<int64_t> rendered{0}, anchor{0};
    std::atomic<bool> running{false}, failed{false};
    int64_t lastXruns=0;
    bool push(Command c) {
        auto w=write.load(std::memory_order_relaxed);
        auto next=(w+1)%queue.size();
        if (next==read.load(std::memory_order_acquire)) return false;
        queue[w]=c; write.store(next,std::memory_order_release); return true;
    }
    bool open() {
        if (stream && !failed.load()) return true;
        close();
        oboe::AudioStreamBuilder b;
        b.setDirection(oboe::Direction::Output)->setPerformanceMode(oboe::PerformanceMode::LowLatency)
         ->setSharingMode(oboe::SharingMode::Exclusive)->setFormat(oboe::AudioFormat::Float)
         ->setChannelCount(2)->setUsage(oboe::Usage::Game)
         ->setDataCallback(this)->setErrorCallback(this);
        if (b.openStream(stream)!=oboe::Result::OK) return false;
        mixer.rate=stream->getSampleRate();
        stream->setBufferSizeInFrames(stream->getFramesPerBurst()*2);
        failed=false;
        lastXruns=0;
        if (stream->requestStart()!=oboe::Result::OK) { close(); return false; }
        return true;
    }
    void close() {
        if (stream) { stream->requestStop(); stream->close(); stream.reset(); }
        mixer.clear(); active=0; running=false; rendered=0; anchor=0; read=0; write=0;
    }
    void onErrorAfterClose(oboe::AudioStream*, oboe::Result) override { failed=true; running=false; }
    oboe::DataCallbackResult onAudioReady(oboe::AudioStream*,void *audio,int32_t frames) override {
        auto r=read.load(std::memory_order_relaxed);
        while (r!=write.load(std::memory_order_acquire)) {
            const auto c=queue[r];
            if (c.kind==1) mixer.on(c.id,c.note,c.ratio,c.gain);
            if (c.kind==2) mixer.off(c.id);
            if (c.kind==3) { mixer.clear(); running=false; }
            if (c.kind==4) { anchor=rendered.load()-c.position*mixer.rate/1000000; running=true; }
            if (c.kind==5) running=false;
            r=(r+1)%queue.size();
        }
        read.store(r,std::memory_order_release);
        float *out=static_cast<float*>(audio);
        const auto first=rendered.load();
        const auto start=anchor.load();
        for (int i=0;i<frames;i++) {
            float value=mixer.frame();
            if (running.load()) {
                const double p=(first+i-start)*static_cast<double>(trackRate)/mixer.rate;
                if (p>=0 && p+1<track.size()) {
                    const auto n=static_cast<size_t>(p);
                    value+=(track[n]+(track[n+1]-track[n])*static_cast<float>(p-n))*trackGain;
                }
            }
            out[2*i]=out[2*i+1]=qin::Mixer::limit(value);
        }
        rendered=first+frames; active=mixer.count();
        return oboe::DataCallbackResult::Continue;
    }
    int64_t positionUs() {
        if (!stream) return 0;
        int64_t position=rendered.load()-stream->getBufferSizeInFrames();
        int64_t frame, nanos;
        if (stream->getTimestamp(CLOCK_MONOTONIC,&frame,&nanos)==oboe::Result::OK) {
            timespec now{}; clock_gettime(CLOCK_MONOTONIC,&now);
            auto nowNanos=now.tv_sec*1000000000LL+now.tv_nsec;
            position=std::min<int64_t>(rendered.load(),frame+(nowNanos-nanos)*mixer.rate/1000000000LL);
        }
        return (position-anchor.load())*1000000/mixer.rate;
    }
};
Engine engine;
std::vector<float> floats(JNIEnv *env,jfloatArray data) {
    std::vector<float> result(env->GetArrayLength(data));
    env->GetFloatArrayRegion(data,0,result.size(),result.data()); return result;
}
}
#define JNI(name) Java_com_pianoforparkinson_piano_1practice_NativePiano_##name
extern "C" JNIEXPORT jfloatArray JNICALL JNI(decodeVorbis)(JNIEnv *e,jobject,jbyteArray data) {
    // Runs on PianoAudio before preparation, never in the render callback.
    const int size=e->GetArrayLength(data);
    auto *encoded=e->GetByteArrayElements(data,nullptr);
    if (!encoded) return nullptr;
    int channels=0, rate=0; short *decoded=nullptr;
    const int frames=stb_vorbis_decode_memory(reinterpret_cast<unsigned char*>(encoded),size,&channels,&rate,&decoded);
    e->ReleaseByteArrayElements(data,encoded,JNI_ABORT);
    if (frames<=0 || frames>22050*600 || channels!=1 || rate!=22050) {
        free(decoded);
        e->ThrowNew(e->FindClass("java/lang/IllegalStateException"),"Invalid bundled Vorbis track");
        return nullptr;
    }
    std::vector<float> pcm(frames);
    for (int i=0;i<frames;i++) pcm[i]=decoded[i]/32768.f;
    free(decoded);
    auto result=e->NewFloatArray(frames);
    if (result) e->SetFloatArrayRegion(result,0,frames,pcm.data());
    return result;
}
extern "C" JNIEXPORT void JNICALL JNI(reset)(JNIEnv*,jobject) {
    engine.close(); engine.track.clear(); engine.track.shrink_to_fit();
    for (auto &sample:engine.mixer.samples) sample=qin::Sample{};
}
extern "C" JNIEXPORT void JNICALL JNI(suspendStream)(JNIEnv*,jobject) { engine.close(); }
extern "C" JNIEXPORT jboolean JNICALL JNI(open)(JNIEnv*,jobject) { return engine.open(); }
extern "C" JNIEXPORT void JNICALL JNI(loadSample)(JNIEnv *e,jobject,jint id,jfloatArray data,jint rate,jint root,jint start,jint end,jint fade) {
    if (id<0 || id>=128 || engine.stream) return;
    auto &s=engine.mixer.samples[id]; s.pcm=floats(e,data); s.rate=rate; s.root=root;
    s.loopStart=start; s.loopEnd=end; s.crossfade=fade;
}
extern "C" JNIEXPORT jboolean JNICALL JNI(command)(JNIEnv*,jobject,jint kind,jint id,jint note,jfloat ratio,jfloat gain,jlong position) {
    if (!engine.stream && kind!=1 && kind!=4) return true;
    if (!engine.open()) return false;
    return engine.push({kind,id,note,ratio,gain,position});
}
extern "C" JNIEXPORT void JNICALL JNI(prepareTrack)(JNIEnv *e,jobject,jfloatArray data,jint rate,jfloat gain,jintArray notes,jintArray ratios,jlongArray starts,jlongArray durations,jlongArray releaseEnds) {
    engine.close();
    engine.track=floats(e,data); engine.trackRate=rate; engine.trackGain=gain;
    // Audition is mixed once on the worker before starting, never on UI frames.
    const int count=e->GetArrayLength(notes);
    std::vector<int> ids(count), rates(count);
    std::vector<int64_t> begin(count), length(count), end(count);
    e->GetIntArrayRegion(notes,0,count,ids.data()); e->GetIntArrayRegion(ratios,0,count,rates.data());
    e->GetLongArrayRegion(starts,0,count,reinterpret_cast<jlong*>(begin.data()));
    e->GetLongArrayRegion(durations,0,count,reinterpret_cast<jlong*>(length.data()));
    e->GetLongArrayRegion(releaseEnds,0,count,reinterpret_cast<jlong*>(end.data()));
    const int savedRate=engine.mixer.rate;
    engine.mixer.rate=rate;
    for (auto &v:engine.track) v*=.35f;
    for (int i=0;i<count;i++) {
        engine.mixer.on(i+1,ids[i],rates[i]/1000.f,.65f);
        auto &voice=engine.mixer.voices[0];
        const int64_t offset=begin[i]*rate/1000000;
        const int64_t gate=length[i]*rate/1000000;
        const int64_t tail=static_cast<int64_t>(engine.mixer.releaseSeconds*rate);
        for (int64_t j=0;j<gate+tail && offset+j<end[i]*rate/1000000 && offset+j<static_cast<int64_t>(engine.track.size());j++) {
            if (j==gate) voice.releasing=true;
            if (offset+j>=0 && voice.id) engine.track[offset+j]+=engine.mixer.voiceFrame(voice);
        }
        engine.mixer.clear();
    }
    engine.mixer.rate=savedRate;
}
extern "C" JNIEXPORT jlongArray JNICALL JNI(state)(JNIEnv *e,jobject) {
    int64_t xrun=0;
    if (engine.stream) {
        const auto result=engine.stream->getXRunCount();
        if (result) xrun=result.value();
        if (xrun>engine.lastXruns) {
            const int burst=engine.stream->getFramesPerBurst();
            const int current=engine.stream->getBufferSizeInFrames();
            engine.stream->setBufferSizeInFrames(std::min(current+burst,8*burst));
            engine.lastXruns=xrun;
        }
    }
    jlong values[]={engine.positionUs(),engine.running.load(),engine.active.load(),engine.failed.load(),xrun,engine.mixer.rate};
    auto result=e->NewLongArray(6); e->SetLongArrayRegion(result,0,6,values); return result;
}
