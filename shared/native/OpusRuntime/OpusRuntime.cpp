#include "OpusRuntime.h"
#include <ctranslate2/models/model.h>
#include <ctranslate2/models/sequence_to_sequence.h>
#include <ctranslate2/utils.h>
#include <sentencepiece_processor.h>
#include <atomic>
#include <cstring>
#include <filesystem>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
struct Cancelled {};
thread_local const std::atomic_bool *active_flag = nullptr;
thread_local std::string last_error;
struct ScopedFlag {
    const std::atomic_bool *previous;
    explicit ScopedFlag(const std::atomic_bool *flag) : previous(active_flag) { active_flag = flag; }
    ~ScopedFlag() { active_flag = previous; }
};
struct Direction {
    sentencepiece::SentencePieceProcessor source, target;
    std::string path;
};
struct Context {
    // Keyed by subdirectory: en-zle/zle-en (English package) or e.g. de-zle/zle-de.
    std::map<std::string, Direction> directions;
    std::shared_ptr<const ctranslate2::models::Model> model;
    std::unique_ptr<ctranslate2::models::SequenceToSequenceReplica> replica;
    Direction *loaded = nullptr;
};
bool slavic(const std::string& language) { return language == "ru" || language == "uk" || language == "be"; }
Direction& named(Context& context, const std::string& name) {
    const auto found = context.directions.find(name);
    if (found == context.directions.end()) throw std::invalid_argument("Unsupported OPUS direction");
    return found->second;
}
// Legacy language-pair API (English package): East Slavic is the "zle" group and a target
// marker is needed only into it. Catalog-driven callers pass the direction and marker directly.
std::string legacy_name(const std::string& source, const std::string& target) {
    const auto group = [](const std::string& language) { return slavic(language) ? std::string("zle") : language; };
    if (group(source) == group(target)) throw std::invalid_argument("Unsupported OPUS direction");
    return group(source) + "-" + group(target);
}
std::string legacy_marker(const std::string& source, const std::string& target) {
    if (slavic(source) || !slavic(target)) return "";
    return target == "ru" ? ">>rus<<" : target == "uk" ? ">>ukr<<" : ">>bel<<";
}
std::vector<std::string> encode(Direction& direction, const std::string& text, const std::string& marker) {
    std::vector<std::string> pieces;
    auto status = direction.source.Encode(text, &pieces);
    if (!status.ok()) throw std::runtime_error(status.ToString());
    // Multi-target models need a marker. MarianTokenizer removes it before SentencePiece
    // and prepends it literally.
    if (!marker.empty()) pieces.insert(pieces.begin(), marker);
    pieces.push_back("</s>");
    return pieces;
}
void open_direction(Direction& direction, const std::filesystem::path& root) {
    direction.path = root.string();
    for (const char *name : {"model.bin", "config.json", "shared_vocabulary.json"}) {
        if (!std::filesystem::is_regular_file(root / name)) throw std::runtime_error("Incomplete OPUS package");
    }
    auto source_status = direction.source.Load((root / "source.spm").string());
    auto target_status = direction.target.Load((root / "target.spm").string());
    if (!source_status.ok() || !target_status.ok()) throw std::runtime_error("Invalid OPUS tokenizer");
}
}

// Called once per decoding step by the small, pinned CTranslate2 cancellation patch.
// Direct replica execution keeps this flag on the caller's serial worker thread.
void kat_opus_check_cancel() {
    if (active_flag && active_flag->load(std::memory_order_relaxed)) throw Cancelled{};
}

extern "C" {
void *ot_opus_load(const char *package_path) {
    try {
        last_error.clear();
        if (!package_path) return nullptr;
        auto context = std::make_unique<Context>();
        const std::filesystem::path root(package_path);
        for (const auto& entry : std::filesystem::directory_iterator(root)) {
            const auto name = entry.path().filename().string();
            const auto dash = name.find('-');
            if (!entry.is_directory() || dash == std::string::npos || name.front() == '.') continue;
            open_direction(context->directions[name], entry.path());
        }
        if (context->directions.empty()) throw std::runtime_error("Incomplete OPUS package");
        return context.release();
    } catch (const std::exception& error) { last_error = error.what(); return nullptr; }
    catch (...) { last_error = "Unknown OPUS load error"; return nullptr; }
}
const char *ot_opus_last_error() { return last_error.c_str(); }
void ot_opus_free(void *context) { delete static_cast<Context *>(context); }
void *ot_opus_flag_create() { try { return new std::atomic_bool(false); } catch (...) { return nullptr; } }
void ot_opus_flag_cancel(void *flag) { if (flag) static_cast<std::atomic_bool *>(flag)->store(true, std::memory_order_relaxed); }
void ot_opus_flag_free(void *flag) { delete static_cast<std::atomic_bool *>(flag); }
int ot_opus_count_direction(void *raw, const char *text, const char *name, const char *marker) {
    try {
        if (!raw || !text || !name || !marker) return -1;
        auto& context = *static_cast<Context *>(raw);
        return static_cast<int>(encode(named(context, name), text, marker).size());
    } catch (...) { return -1; }
}
int ot_opus_prepare_direction(void *raw, const char *name, void *flag) {
    try {
        last_error.clear();
        if (!raw || !name) return -1;
        ScopedFlag cancellation(static_cast<std::atomic_bool *>(flag));
        kat_opus_check_cancel();
        auto& context = *static_cast<Context *>(raw);
        auto& selected = named(context, name);
        ctranslate2::set_num_threads(4);
        if (context.loaded != &selected) {
            context.replica.reset(); context.model.reset(); context.loaded = nullptr;
            context.model = ctranslate2::models::Model::load(selected.path, ctranslate2::Device::CPU, 0,
                                                          ctranslate2::ComputeType::INT8_FLOAT32);
            context.replica = context.model->as_sequence_to_sequence();
            context.loaded = &selected;
        }
        kat_opus_check_cancel();
        return 0;
    } catch (const Cancelled&) { return 2; }
    catch (const std::exception& error) { last_error = error.what(); return -1; }
    catch (...) { last_error = "Unknown OPUS preparation error"; return -1; }
}
int ot_opus_run_direction(void *raw, const char *text, const char *name, const char *marker,
                          void *flag, char *output, size_t capacity) {
    if (output && capacity) output[0] = '\0';
    try {
        last_error.clear();
        if (!raw || !text || !name || !marker || !output || !capacity) return -1;
        ScopedFlag cancellation(static_cast<std::atomic_bool *>(flag));
        kat_opus_check_cancel();
        auto& context = *static_cast<Context *>(raw);
        auto& selected = named(context, name);
        const auto input = encode(selected, text, marker);
        if (input.size() > 480) return 1;
        const int prepared = ot_opus_prepare_direction(raw, name, flag);
        if (prepared != 0) return prepared;
        kat_opus_check_cancel();
        ctranslate2::TranslationOptions options;
        options.beam_size = 5;
        options.max_input_length = 0;
        options.max_decoding_length = 512;
        options.return_end_token = true;
        const auto results = context.replica->translate({input}, {}, options);
        kat_opus_check_cancel();
        if (results.empty() || results[0].hypotheses.empty()) return -1;
        auto tokens = results[0].hypotheses[0];
        if (tokens.empty() || tokens.back() != "</s>") return 1;
        tokens.pop_back();
        std::string translated;
        const auto status = selected.target.Decode(tokens, &translated);
        if (!status.ok() || translated.empty()) return -1;
        if (translated.size() + 1 > capacity) return 1;
        std::memcpy(output, translated.c_str(), translated.size() + 1);
        return 0;
    } catch (const Cancelled&) { return 2; }
    catch (const std::exception& error) { last_error = error.what(); return -1; }
    catch (...) { last_error = "Unknown OPUS translation error"; return -1; }
}
int ot_opus_count(void *raw, const char *text, const char *source, const char *target) {
    try {
        if (!source || !target) return -1;
        return ot_opus_count_direction(raw, text, legacy_name(source, target).c_str(), legacy_marker(source, target).c_str());
    } catch (...) { return -1; }
}
int ot_opus_prepare(void *raw, const char *source, const char *target, void *flag) {
    try {
        if (!source || !target) return -1;
        return ot_opus_prepare_direction(raw, legacy_name(source, target).c_str(), flag);
    } catch (const std::exception& error) { last_error = error.what(); return -1; }
    catch (...) { return -1; }
}
int ot_opus_run(void *raw, const char *text, const char *source, const char *target,
                void *flag, char *output, size_t capacity) {
    if (output && capacity) output[0] = '\0';
    try {
        if (!source || !target) return -1;
        return ot_opus_run_direction(raw, text, legacy_name(source, target).c_str(), legacy_marker(source, target).c_str(), flag, output, capacity);
    } catch (const std::exception& error) { last_error = error.what(); return -1; }
    catch (...) { return -1; }
}
}
