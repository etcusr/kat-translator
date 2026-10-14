#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "omnivoice_cpu_compat.h"
#if !defined(__aarch64__) || defined(__ARM_FEATURE_DOTPROD)
#error Compile this regression for baseline ARM64 without DOTPROD.
#endif
static uint32_t seed=0x627493a1u;
static uint32_t random_word() { seed^=seed<<13;seed^=seed>>17;seed^=seed<<5;return seed; }
int main() {
    unsigned old_mismatches=0,cases=0;
    for (unsigned test=0;test<10032;++test) {
        int8_t a[16],b[16];int32_t initial[4],expected[4],actual[4],old[4];
        for (int i=0;i<16;++i) {
            if(test<32) {
                // Sign extremes, sparse lanes, and asymmetric products expose
                // grouping errors which a scalar-total-only test would miss.
                a[i]=(test<16 && i!=int(test))?0:((i+test)%2 ? -128 : 127);
                b[i]=test>=16?((i+test/2)%2 ? -128 : 127):int8_t((i+1)*7*(test%2 ? -1 : 1));
            } else { a[i]=int8_t(random_word()&255);b[i]=int8_t(random_word()&255); }
        }
        for(int lane=0;lane<4;++lane) {
            initial[lane]=int32_t(random_word()%2000001)-1000000;
            int64_t sum=initial[lane];
            for(int j=0;j<4;++j)sum+=int64_t(a[4*lane+j])*int64_t(b[4*lane+j]);
            expected[lane]=int32_t(sum);
        }
        vst1q_s32(actual,ggml_vdotq_s32(vld1q_s32(initial),vld1q_s8(a),vld1q_s8(b)));
        vst1q_s32(old,kat_omnivoice_original_vdotq_s32(vld1q_s32(initial),vld1q_s8(a),vld1q_s8(b)));
        for(int lane=0;lane<4;++lane) {
            if(actual[lane]!=expected[lane]) { std::fprintf(stderr,"case=%u lane=%d expected=%d actual=%d\n",test,lane,expected[lane],actual[lane]);return 1; }
            old_mismatches+=old[lane]!=expected[lane];
        }
        ++cases;
    }
    if(!old_mismatches)return 2;
    std::printf("PASS %u scalar-reference cases; original fallback mismatched %u lanes\n",cases,old_mismatches);
}
