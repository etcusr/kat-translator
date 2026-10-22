#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#include "TranslationRuntime.h"
#include "llama.h"
#ifdef KAT_IOS_MTP
#include "IndexMTP.h"
#endif
#include <atomic>
#include <cstdio>
#include <chrono>
#include <cstring>
#include <mutex>
#include <new>
#include <stdexcept>
#include <memory>
#include <string>
#include <vector>
#include <algorithm>
#include <cmath>
#ifdef __ANDROID__
#include <android/log.h>
#include <cstdlib>
#include <map>
// Opt-in instrumentation only; normal translations do not collect per-stage data.
struct KatProfile {
    bool enabled = std::getenv("KAT_INDEX_PROFILE") != nullptr;
    std::chrono::steady_clock::time_point last = std::chrono::steady_clock::now();
    std::map<std::string, std::pair<double, int>> stages;
    KatProfile() { if (enabled) std::fprintf(stderr, "KAT_PROFILE_BEGIN\n"); }
    void mark(const char *name) {
        if (!enabled) return;
        const auto now = std::chrono::steady_clock::now();
        auto &row = stages[name]; row.first += std::chrono::duration<double, std::milli>(now-last).count(); ++row.second; last=now;
    }
    ~KatProfile() {
        if (!enabled) return;
        mark("finish");
        for (const auto &row : stages) std::fprintf(stderr,"KAT_STAGE %s %.3f ms %d calls\n",row.first.c_str(),row.second.first,row.second.second);
        std::fprintf(stderr,"KAT_PROFILE_END\n");
    }
};
#define KAT_MARK(name) profile.mark(name)
#else
#define KAT_MARK(name) ((void)0)
#endif
struct Engine {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
#ifdef KAT_IOS_MTP
    std::unique_ptr<IndexMTP> mtp;
#endif
    // Text generated so far by the running request; read from another thread while decoding.
    std::mutex partial_mutex;
    std::string partial;
    void publish(const std::string &text) { std::lock_guard<std::mutex> lock(partial_mutex); partial = text; }
    ~Engine() {
#ifdef KAT_IOS_MTP
        if (mtp) { mtp.reset(); ctx = nullptr; }
#endif
        if (ctx) llama_free(ctx);
        if (model) llama_model_free(model);
    }
};
using Flag = std::atomic_bool;
static bool abort_run(void *flag) { return static_cast<Flag *>(flag)->load(std::memory_order_relaxed); }
static std::once_flag init_once;
void *ot_mt_load(const char *path) {
#if defined(__APPLE__) && TARGET_OS_SIMULATOR
    // MTLSimDevice rejects the mapped-buffer path used by ggml. Physical devices
    // keep their existing GPU/MTP configuration; Simulator is for UI checks.
    return ot_mt_load_config(path, 4, 0, 0);
#else
    return ot_mt_load_config(path, 4, 99, 1);
#endif
}
void *ot_mt_load_config(const char *path, int threads, int gpu_layers, int flash_attention) {
    if (!path || !*path || threads < 1 || threads > 32 || gpu_layers < 0 || (flash_attention != 0 && flash_attention != 1)) return nullptr;
    try {
        std::call_once(init_once, [] { llama_log_set([](ggml_log_level level, const char *message, void *) {
#ifdef __ANDROID__
            if (level >= GGML_LOG_LEVEL_INFO) __android_log_write(level == GGML_LOG_LEVEL_ERROR ? ANDROID_LOG_ERROR : ANDROID_LOG_INFO, "KatIndex", message);
#else
            if (level == GGML_LOG_LEVEL_ERROR) std::fputs(message, stderr);
#endif
        }, nullptr); llama_backend_init(); });
#ifdef KAT_IOS_MTP
        // A failed speculative allocation falls back to a fresh ordinary model/context.
        for (bool useMTP : {gpu_layers > 0, false}) {
#endif
        auto e = std::make_unique<Engine>();
        auto mp = llama_model_default_params(); mp.n_gpu_layers = gpu_layers;
#ifdef __ANDROID__
        // Respect the Vulkan device's mmap_support capability (false on Mali iGPUs).
        mp.load_mode = LLAMA_LOAD_MODE_AUTO;
#else
        mp.load_mode = LLAMA_LOAD_MODE_MMAP;
#endif
#ifdef KAT_IOS_MTP
        mp.load_mtp = useMTP;
#endif
        ggml_backend_dev_t cpu_only_devices[] = {nullptr};
        if (gpu_layers == 0) mp.devices = cpu_only_devices;
        e->model = llama_model_load_from_file(path, mp);
        if (!e->model) {
#ifdef KAT_IOS_MTP
            if (useMTP) continue;
#endif
            return nullptr;
        }
        auto cp = llama_context_default_params(); cp.n_ctx = 2048; cp.n_batch = 512; cp.n_ubatch = 128;
        if (gpu_layers == 0) { cp.offload_kqv = false; cp.op_offload = false; }
        cp.n_threads = threads; cp.n_threads_batch = threads; cp.flash_attn_type = flash_attention ? LLAMA_FLASH_ATTN_TYPE_ENABLED : LLAMA_FLASH_ATTN_TYPE_DISABLED;
#ifdef KAT_IOS_MTP
        if (useMTP) {
            try { e->mtp = IndexMTP::create(e->model, cp); } catch (...) {}
            if (!e->mtp) continue;
            e->ctx = e->mtp->target();
            std::fputs("Kat Index: MTP enabled, 2 draft tokens\n", stderr);
        } else
#endif
        e->ctx = llama_init_from_model(e->model, cp);
        if (!e->ctx) return nullptr;
        return e.release();
#ifdef KAT_IOS_MTP
        }
        return nullptr;
#endif
    } catch (...) { return nullptr; }
}
void ot_mt_free(void *handle) { delete static_cast<Engine *>(handle); }
void *ot_mt_flag_create(void) { return new (std::nothrow) Flag(false); }
void ot_mt_flag_cancel(void *flag) { if (flag) static_cast<Flag *>(flag)->store(true, std::memory_order_relaxed); }
void ot_mt_flag_free(void *flag) { delete static_cast<Flag *>(flag); }
int ot_mt_partial(void *handle, char *out, size_t capacity) {
    if (!handle || !out || capacity < 1) return -1;
    auto *e = static_cast<Engine *>(handle);
    std::lock_guard<std::mutex> lock(e->partial_mutex);
    if (e->partial.size() + 1 > capacity) return (int) e->partial.size();
    std::memcpy(out, e->partial.c_str(), e->partial.size() + 1);
    return (int) e->partial.size();
}
static std::vector<llama_token> tokenize(const llama_vocab *vocab, const char *text, bool controls) {
    int n = llama_tokenize(vocab, text, (int) strlen(text), nullptr, 0, false, controls);
    std::vector<llama_token> tokens(n < 0 ? -n : n);
    if (!tokens.empty()) {
        n = llama_tokenize(vocab, text, (int) strlen(text), tokens.data(), (int) tokens.size(), false, controls);
        if (n < 0) throw std::runtime_error("tokenize"); tokens.resize(n);
    } return tokens;
}
static std::vector<llama_token> prompt(Engine *e, const char *prefix, const char *text, const char *suffix) {
    const auto *vocab = llama_model_get_vocab(e->model);
    auto result = tokenize(vocab, prefix, true);
    auto content = tokenize(vocab, text, false); result.insert(result.end(), content.begin(), content.end());
    auto end = tokenize(vocab, suffix, true); result.insert(result.end(), end.begin(), end.end()); return result;
}
int ot_mt_count(void *handle, const char *prefix, const char *text, const char *suffix) {
    if (!handle || !prefix || !text || !suffix) return -1;
    try { return (int) prompt(static_cast<Engine *>(handle), prefix, text, suffix).size(); } catch (...) { return -1; }
}
int ot_mt_tokens(void *handle, const char *prefix, const char *text, const char *suffix, int *out, size_t capacity) {
    if (!handle || !prefix || !text || !suffix) return -1;
    try {
        auto values = prompt(static_cast<Engine *>(handle), prefix, text, suffix);
        if (out && capacity >= values.size()) std::copy(values.begin(), values.end(), out);
        return (int) values.size();
    } catch (...) { return -1; }
}
int ot_mt_run(void *handle, const char *prefix, const char *text, const char *suffix, void *flag, char *out, size_t capacity, double *first) {
    if (!handle || !prefix || !text || !suffix || !flag || !out || !first || capacity < 1) return -1;
    out[0] = 0; *first = -1;
    if (abort_run(flag)) return 2;
    try {
#ifdef __ANDROID__
        KatProfile profile;
#endif
        auto *e = static_cast<Engine *>(handle); const auto *vocab = llama_model_get_vocab(e->model);
        if (!e->ctx) return -1;
        auto tokens = prompt(e, prefix, text, suffix); if (tokens.empty() || tokens.size() > 1536) return 1;
        const size_t context_capacity = llama_n_ctx_seq(e->ctx);
        if (tokens.size() >= context_capacity) return 1;
        const size_t output_budget = context_capacity - tokens.size();
#ifdef KAT_IOS_MTP
        e->publish({});
        if (e->mtp) return e->mtp->run(tokens, static_cast<Flag *>(flag), out, capacity, first, [e](const std::string &text) { e->publish(text); });
#endif
        KAT_MARK("tokenize");
        e->publish({});
        if (abort_run(flag)) return 2;
        llama_synchronize(e->ctx);
        KAT_MARK("wait_previous");
        llama_memory_clear(llama_get_memory(e->ctx), true);
        KAT_MARK("clear_memory");
        llama_set_abort_callback(e->ctx, abort_run, flag);
        struct ClearCallback { llama_context *ctx; ~ClearCallback() { llama_set_abort_callback(ctx, nullptr, nullptr); } } clear{e->ctx};
        const auto started = std::chrono::steady_clock::now();
        KAT_MARK("setup");
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_INFO, "KatIndex", "prefill begin: %zu tokens", tokens.size());
#endif
        for (size_t offset = 0; offset < tokens.size(); offset += 512) {
            if (abort_run(flag)) return 2;
            int n = (int) std::min<size_t>(512, tokens.size() - offset);
            auto batch = llama_batch_get_one(tokens.data() + offset, n);
            if (llama_decode(e->ctx, batch)) return abort_run(flag) ? 2 : -1;
        }
        llama_sampler *sampler = llama_sampler_init_greedy();
        KAT_MARK("prefill_submit");
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_INFO, "KatIndex", "prefill complete: %.3f s", std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count());
#endif
        struct FreeSampler { llama_sampler *p; ~FreeSampler() { llama_sampler_free(p); } } cleanup{sampler};
        std::string result;
        // Use free positions in the existing context, without growing its allocation.
        // After the last available position is decoded, allow an EOG check only.
        for (size_t i = 0; i <= output_budget; ++i) {
#ifdef __ANDROID__
            if (i && i % 32 == 0) __android_log_print(ANDROID_LOG_INFO, "KatIndex", "generated %zu tokens", i);
#endif
            if (abort_run(flag)) return 2;
#ifdef __ANDROID__
            const float *logits = llama_get_logits_ith(e->ctx, -1);
            if (!logits || std::any_of(logits, logits + llama_vocab_n_tokens(vocab), [](float value) { return std::isnan(value); })) {
                __android_log_print(ANDROID_LOG_ERROR, "KatIndex", "Invalid logits at generated token %zu", i);
                return -2;
            }
            KAT_MARK(i == 0 ? "prefill_wait_and_validate" : "decode_wait_and_validate");
#endif
            llama_token token = llama_sampler_sample(sampler, e->ctx, -1);
            KAT_MARK("sample");
            if (llama_vocab_is_eog(vocab, token)) {
                if (result.empty() || result.size() + 1 > capacity) return -1;
                memcpy(out, result.c_str(), result.size() + 1); return 0;
            }
            if (i == output_budget) return 1;
            if (*first < 0) *first = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
            char piece[256]; int n = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
            if (n < 0) { std::vector<char> large(-n); n = llama_token_to_piece(vocab, token, large.data(), (int) large.size(), 0, false); if (n < 0) return -1; result.append(large.data(), n); }
            else result.append(piece, n);
            if (result.size() + 1 > capacity) return 1;
            e->publish(result);
            KAT_MARK("detokenize");
            auto batch = llama_batch_get_one(&token, 1);
            if (llama_decode(e->ctx, batch)) return abort_run(flag) ? 2 : -1;
            KAT_MARK("decode_submit");
        }
        return 1;
    } catch (...) { return -1; }
}
