#pragma once
// Built only into the iOS runtime. The model is owned by Engine and outlives both contexts.
#include "llama.h"
#include <atomic>
#include <functional>
#include <string>
#include <memory>
#include <vector>

class IndexMTP {
public:
    static std::unique_ptr<IndexMTP> create(llama_model *, llama_context_params);
    ~IndexMTP();
    llama_context *target() const { return target_; }
    int run(const std::vector<llama_token> &, std::atomic_bool *, char *, size_t, double *,
            const std::function<void(const std::string &)> &partial);
private:
    IndexMTP() = default;
    llama_context *target_ = nullptr;
    llama_context *draft_ = nullptr;
};
