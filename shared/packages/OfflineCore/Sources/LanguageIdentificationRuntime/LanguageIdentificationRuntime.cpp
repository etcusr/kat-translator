#include "LanguageIdentificationRuntime.h"
#include "vendor/fasttext.h"
#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>

extern "C" int kat_language_detect(const char *path, const char *text, KatLanguagePrediction *out) {
    if (!path || !text || !out) return 0;
    *out = {};
    static std::mutex mutex;
    static std::unique_ptr<fasttext::FastText> model;
    std::lock_guard<std::mutex> guard(mutex);
    try {
        if (!model) {
            auto candidate = std::make_unique<fasttext::FastText>();
            candidate->loadModel(path);
            model = std::move(candidate);
        }
        std::istringstream input(text);
        std::vector<std::pair<fasttext::real, std::string>> predictions;
        if (!model->predictLine(input, predictions, 2, 0) || predictions.empty()) return 0;
        auto copy = [](const std::string &label, char *destination) {
            const std::string prefix = "__label__";
            if (label.compare(0, prefix.size(), prefix) != 0) return;
            const auto language = label.substr(prefix.size());
            if (language.size() < 24) std::memcpy(destination, language.c_str(), language.size() + 1);
        };
        copy(predictions[0].second, out->language);
        out->confidence = predictions[0].first;
        if (predictions.size() > 1) {
            copy(predictions[1].second, out->alternative);
            out->alternativeConfidence = predictions[1].first;
        }
        return out->language[0] != 0;
    } catch (...) { return 0; }
}
