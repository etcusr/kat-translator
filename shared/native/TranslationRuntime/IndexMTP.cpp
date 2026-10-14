#include "IndexMTP.h"
#include "common.h"
#include "sampling.h"
#include "speculative.h"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <stdexcept>

namespace {
constexpr int draftTokens = 2;
bool cancelled(void *flag) { return static_cast<std::atomic_bool *>(flag)->load(std::memory_order_relaxed); }
common_params_speculative parameters(llama_context *target, llama_context *draft) {
    common_params_speculative params;
    params.types = {COMMON_SPECULATIVE_TYPE_DRAFT_MTP};
    params.draft.n_max = draftTokens;
    params.draft.p_min = 0;
    params.draft.backend_sampling = true;
    params.draft.ctx_tgt = target;
    params.draft.ctx_dft = draft;
    return params;
}
struct Callbacks {
    llama_context *target, *draft;
    ~Callbacks() {
        // Drain work before releasing request-owned cancellation/sampling state.
        llama_synchronize(target);
        llama_synchronize(draft);
        llama_set_abort_callback(target, nullptr, nullptr);
        llama_set_abort_callback(draft, nullptr, nullptr);
    }
};
}

IndexMTP::~IndexMTP() {
    if (draft_) llama_free(draft_);
    if (target_) llama_free(target_);
}

std::unique_ptr<IndexMTP> IndexMTP::create(llama_model *model, llama_context_params cp) {
    if (llama_model_n_layer_nextn(model) < 1) return nullptr;
    auto result = std::unique_ptr<IndexMTP>(new IndexMTP());
    const auto params = parameters(nullptr, nullptr);
    const auto limits = common_speculative_get_output_limits(cp.n_batch, 1, draftTokens);
    cp.n_outputs_max = limits.total;
    cp.n_outputs_max_per_seq = limits.per_seq;
    // Index is recurrent: partial draft acceptance must roll back recurrent state too.
    cp.n_rs_seq = params.need_n_rs_seq();
    result->target_ = llama_init_from_model(model, cp);
    if (!result->target_) return nullptr;
    cp.ctx_type = LLAMA_CONTEXT_TYPE_MTP;
    cp.ctx_other = result->target_;
    cp.n_rs_seq = 0;
    cp.n_outputs_max = 1;
    cp.n_outputs_max_per_seq = 1;
    result->draft_ = llama_init_from_model(model, cp);
    if (!result->draft_) return nullptr;
    return result;
}

int IndexMTP::run(const std::vector<llama_token> &input, std::atomic_bool *flag,
                  char *out, size_t capacity, double *first) {
    // C API validates pointers and token budget before dispatching here.
    try {
        if (cancelled(flag)) return 2;
        llama_synchronize(target_);
        llama_synchronize(draft_);
        llama_memory_clear(llama_get_memory(target_), true);
        llama_memory_clear(llama_get_memory(draft_), true);
        const auto *model = llama_get_model(target_);
        const auto *vocab = llama_model_get_vocab(model);
        const int context = static_cast<int>(llama_n_ctx_seq(target_));
        const int budget = context - static_cast<int>(input.size());
        common_params_sampling sampling;
        sampling.temp = 0;
        sampling.samplers = {COMMON_SAMPLER_TYPE_TEMPERATURE};
        common_sampler_ptr sampler(common_sampler_init(model, sampling));
        auto params = parameters(target_, draft_);
        common_speculative_ptr spec(common_speculative_init(params, 1));
        if (!sampler || !spec) return -1;
        llama_set_abort_callback(target_, cancelled, flag);
        llama_set_abort_callback(draft_, cancelled, flag);
        Callbacks callbacks{target_, draft_};
        // All sampler/speculator state belongs to this request, including cancellation recovery.
        const auto started = std::chrono::steady_clock::now();
        common_batch batch(target_);
        const size_t batchSize = llama_n_batch(target_);
        for (size_t offset = 0; offset + 1 < input.size(); offset += batchSize) {
            if (cancelled(flag)) return 2;
            batch.clear();
            const size_t end = std::min(input.size() - 1, offset + batchSize);
            for (size_t i = offset; i < end; ++i) batch.add(input[i], static_cast<llama_pos>(i), 0, false);
            if (llama_process(target_, LLAMA_PROCESS_TYPE_DECODE, batch.get())) return cancelled(flag) ? 2 : -1;
            if (cancelled(flag)) return 2;
            if (!common_speculative_process(spec.get(), batch)) return cancelled(flag) ? 2 : -1;
        }
        llama_token last = input.back();
        llama_tokens past(input.begin(), input.end() - 1);
        past.reserve(context);
        int position = static_cast<int>(past.size());
        int emitted = 0;
        common_speculative_begin(spec.get(), 0, past);
        std::string result;
        while (emitted <= budget) {
            if (cancelled(flag)) return 2;
            llama_tokens draft;
            int maxDraft = std::max(0, std::min(context - position - 2, budget - emitted - 1));
            common_speculative_get_draft_params(spec.get(), 0) = {true, maxDraft, position, last, &past, &draft};
            // Upstream treats n_max == 0 as unlimited, not zero. Near the context
            // boundary use target-only verification, including the final EOG check.
            if (maxDraft > 0) common_speculative_draft(spec.get());
            if (cancelled(flag)) return 2;
            if (!llama_memory_seq_rm(llama_get_memory(draft_), 0, position, -1)) return -1;
            batch.clear();
            batch.add(last, position++, 0, true);
            for (size_t i = 0; i < draft.size(); ++i) batch.add(draft[i], position + static_cast<int>(i), 0, true);
            if (llama_process(target_, LLAMA_PROCESS_TYPE_DECODE, batch.get())) return cancelled(flag) ? 2 : -1;
            if (cancelled(flag)) return 2;
            if (!common_speculative_process(spec.get(), batch)) return cancelled(flag) ? 2 : -1;
            if (cancelled(flag)) return 2;
            auto verified = common_sampler_sample_and_accept_n(sampler.get(), target_, draft);
            if (verified.empty()) return -1;
            common_speculative_accept(spec.get(), 0, verified.size() - 1);
            position += static_cast<int>(verified.size()) - 1;
            bool eos = false;
            for (auto token : verified) {
                past.push_back(last);
                last = token;
                if (llama_vocab_is_eog(vocab, token)) { eos = true; break; }
                if (emitted == budget) return 1;
                if (*first < 0) *first = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
                ++emitted;
                result += common_token_to_piece(target_, token);
                if (result.size() + 1 > capacity) return 1;
            }
            if (cancelled(flag)) return 2;
            if (!llama_memory_seq_rm(llama_get_memory(target_), 0, position, -1) ||
                !llama_memory_seq_rm(llama_get_memory(draft_), 0, position, -1)) return -1;
            if (eos) {
                if (result.empty()) return -1;
                std::memcpy(out, result.c_str(), result.size() + 1);
                return 0;
            }
        }
        return 1;
    } catch (...) { return cancelled(flag) ? 2 : -1; }
}
