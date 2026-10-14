#ifndef KAT_LANGUAGE_IDENTIFICATION_H
#define KAT_LANGUAGE_IDENTIFICATION_H
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    char language[24];
    char alternative[24];
    float confidence;
    float alternativeConfidence;
} KatLanguagePrediction;
int kat_language_detect(const char *model_path, const char *text, KatLanguagePrediction *prediction);
#ifdef __cplusplus
}
#endif
#endif
