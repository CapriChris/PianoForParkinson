#include "../../android/app/src/main/cpp/piano_mixer.h"
#include <cassert>
#include <iostream>

int main() {
    qin::Mixer m;
    m.rate=48000;
    for (int root=36;root<=84;root+=3) {
        auto &s=m.samples[root];
        s.rate=24000; s.root=root; s.loopStart=60000; s.loopEnd=108000; s.crossfade=2048;
        s.pcm.resize(6*s.rate);
        for (size_t i=0;i<s.pcm.size();i++)
            s.pcm[i]=.1f*std::sin(i*2*3.141592653589793*440*std::pow(2.,(root-69)/12.)/s.rate);
    }
    assert(m.on(1,0,1,1));
    double energy=0; float previous=0,maxJump=0;
    for (int i=0;i<8*m.rate;i++) {
        const float v=m.frame();
        if (i>7*m.rate) energy+=v*v;
        maxJump=std::max(maxJump,std::abs(v-previous)); previous=v;
    }
    assert(m.count()==1 && std::sqrt(energy/m.rate)>.025);
    assert(maxJump<.05); // loop and overlap must not produce a hard splice
    m.off(1);
    for(int i=0;i<static_cast<int>(m.rate*.27);i++) m.frame();
    assert(m.count()==0);
    assert(m.on(2,5,1,1));
    int crossings=0; previous=0;
    for(int i=0;i<m.rate;i++) {const float v=m.frame(); if(v>0 && previous<=0) crossings++; previous=v;}
    assert(std::abs(crossings-440)<=1);
    m.clear();
    for(int i=0;i<32;i++) assert(m.on(i+1,0,1,.65));
    assert(!m.on(100,0,1,.65));
    for(int i=0;i<480;i++) assert(std::abs(qin::Mixer::limit(m.frame()))<=.990001);
    m.clear(); assert(m.count()==0); assert(!m.on(1,99,1,1));
    std::cout<<"PASS: sustain 8s, continuous overlap, key release, A4 pitch, polyphony and output headroom\n";
}
