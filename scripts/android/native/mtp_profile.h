#pragma once
#include "llama.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>

// Diagnostic only: fences deliberately serialize stages. Do not use these
// timings as unprofiled application latency or sum them with Vulkan timestamps.
struct KatMtpStage {
    const char *name;
    llama_context *target, *draft;
    int tokens;
    bool enabled;
    std::chrono::steady_clock::time_point start;
    KatMtpStage(const char *name, llama_context *target, llama_context *draft, int tokens)
        : name(name), target(target), draft(draft), tokens(tokens), enabled(std::getenv("KAT_MTP_PROFILE")!=nullptr) {
        if(enabled) { sync(); start=std::chrono::steady_clock::now(); }
    }
    void sync() { if(target)llama_synchronize(target);if(draft && draft!=target)llama_synchronize(draft); }
    ~KatMtpStage() {
        if(!enabled)return;
        sync();
        const double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
        std::fprintf(stderr,"KAT_MTP_STAGE name=%s tokens=%d ms=%.6f\n",name,tokens,ms);
    }
};
