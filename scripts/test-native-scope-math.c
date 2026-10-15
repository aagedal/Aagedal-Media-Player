// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
// Run with clang -fsanitize=address,undefined -O1 -g -arch arm64.
#include "../docs/dependency-patches/scopes/scope_math.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    // Independently known ST 2084 and fixed-gamma HLG anchors.
    assert(fabsf(scope_nits(0.50807842f,1,10000)-100) < .05);
    assert(fabsf(scope_nits(0.7518271f,1,10000)-1000) < .5);
    assert(fabsf(scope_nits(1,1,10000)-10000) < 1);
    assert(fabsf(scope_nits(1,2,1000)-1000) < .1);
    uint16_t src[16*16*4];
    for (int i=0;i<16*16;i++) {
        src[i*4]=i*257;src[i*4+1]=(255-i)*257;
        src[i*4+2]=(i%16)*4369;src[i*4+3]=65535;
    }
    const int widths[]={64,360,720,1080,1440};
    for(int t=0;t<3;t++) for(int m=0;m<8;m++) for(int k=0;k<5;k++) {
        int w=widths[k],h=(int)round(w*9.0/16);
        struct scope_plots p={.w=w,.h=h,.wave=calloc(w*h,4),.parade=calloc(w*h,4),.vector=calloc(h*h,4)};
        assert(scope_compute(src,16,16,16*8,(m%4)*90,m>=4,t!=0,t,t==1?10000:1000,p));
        // Premultiplied waveform colors must never exceed their alpha.
        for(int i=0;i<w*h;i++)for(int c=0;c<3;c++)assert(p.wave[4*i+c]<=p.wave[4*i+3]);
        assert(!scope_compute(src,16,16,1,0,false,false,t,1000,p));
        assert(!scope_compute(src,16,16,128,45,false,false,t,1000,p));
        free(p.wave);free(p.parade);free(p.vector);
    }
    puts("NATIVE_SCOPE_MATH_ACCEPTANCE: 120 transfer/orientation/resolution cases, ASan/UBSan");
}
