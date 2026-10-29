#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <vector>

namespace qin {
struct Sample {
    std::vector<float> pcm;
    int rate = 24000, root = -1, loopStart = 0, loopEnd = 0, crossfade = 0;
};
struct Voice {
    int id = 0, sample = 0;
    double position = 0, step = 1, age = 0;
    float gain = 0, envelope = 1;
    bool releasing = false;
};
// No allocation, decoding, JNI, blocking, or locks in the render path.
class Mixer {
public:
    std::array<Sample, 128> samples;
    std::array<Voice, 32> voices{};
    int rate = 48000;
    float releaseSeconds = .26f;
    int select(int note, float ratio, double &step) const {
        static const int roots[] = {60,62,64,65,67,69,71};
        if (note < 0 || note > 9) return -1;
        int slot = note;
        if (note < 7) {
            const double target = roots[note] + std::round(12 * std::log2(ratio));
            int distance = 1000;
            for (int i = 36; i <= 84; i += 3) {
                if (!samples[i].pcm.empty() && std::abs(i-target) < distance) {
                    slot = i; distance = static_cast<int>(std::abs(i-target));
                }
            }
            step = samples[slot].rate * std::pow(2., (target-samples[slot].root)/12.) / rate;
        } else step = static_cast<double>(samples[slot].rate) / rate;
        return samples[slot].pcm.empty() ? -1 : slot;
    }
    bool on(int id, int note, float ratio, float gain) {
        double step;
        int slot = select(note, ratio, step);
        if (slot < 0) return false;
        for (auto &v : voices) if (!v.id) {
            v = Voice{id,slot,0,step,0,gain,1,false}; return true;
        }
        return false;
    }
    void off(int id) { for (auto &v : voices) if (v.id == id) v.releasing = true; }
    void clear() { voices.fill(Voice{}); }
    int count() const { int n=0; for (const auto &v : voices) n += v.id != 0; return n; }
    static float at(const Sample &s, double p) {
        const auto i = static_cast<size_t>(p);
        if (i + 1 >= s.pcm.size()) return 0;
        return s.pcm[i] + (s.pcm[i+1]-s.pcm[i]) * static_cast<float>(p-i);
    }
    float voiceFrame(Voice &v) {
        const auto &s = samples[v.sample];
        if (v.position + 1 >= s.pcm.size()) { v.id = 0; return 0; }
        float value = at(s, v.position);
        // Loop continuation also applies during release so releasing in an
        // overlap cannot jump abruptly back to the original recording tail.
        if (s.loopEnd > s.loopStart && s.crossfade > 0) {
            if (v.position >= s.loopEnd - s.crossfade) {
                const double blend = (v.position - (s.loopEnd-s.crossfade)) / s.crossfade;
                value = value * static_cast<float>(1-blend) +
                    at(s, s.loopStart + v.position-(s.loopEnd-s.crossfade)) * static_cast<float>(blend);
            }
            const double loopAge = std::max(0., v.age - static_cast<double>(s.loopEnd)/s.rate);
            if (loopAge>0) value *= static_cast<float>(std::exp(-.12 * loopAge));
        }
        const float result = value * v.gain * v.envelope;
        v.position += v.step;
        v.age += 1. / rate;
        if (s.loopEnd > s.loopStart && v.position >= s.loopEnd)
            v.position = s.loopStart+s.crossfade + (v.position-s.loopEnd);
        if (v.releasing) {
            v.envelope -= 1.f / (releaseSeconds*rate);
            if (v.envelope <= 0) v.id=0;
        }
        return result;
    }
    float frame() {
        float value = 0;
        for (auto &v : voices) if (v.id) value += voiceFrame(v);
        return value;
    }
    static float limit(float v) {
        const float a = std::abs(v);
        return a <= .85f ? v : std::copysign(.85f + .14f*std::tanh((a-.85f)/.14f), v);
    }
};
}
