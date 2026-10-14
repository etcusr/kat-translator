#include "media_jni_util.h"
#include "omnivoice.h"
extern "C" {
#include "ASR/WhisperCancellation.h"
}
#include <memory>
#include <mutex>
#include <cstring>
#include <sstream>
#include "ggml.h"

namespace {
// Both upstream log callbacks are process-wide. Keep their storage alive and
// serialize OmniVoice calls so diagnostics cannot cross-contaminate requests.
std::mutex operation_mutex, diagnostic_mutex;
char diagnostics[8192] = {};
size_t diagnostic_size = 0;
void append_diagnostic(const char *message) noexcept {
 if (!message) return;
 std::lock_guard<std::mutex> lock(diagnostic_mutex);
 const size_t available = sizeof(diagnostics) - 1 - diagnostic_size;
 if (!available) return;
 if (diagnostic_size) { diagnostics[diagnostic_size++] = '\n'; }
 const size_t count = strnlen(message, sizeof(diagnostics) - 1 - diagnostic_size);
 memcpy(diagnostics + diagnostic_size, message, count);
 diagnostic_size += count; diagnostics[diagnostic_size] = 0;
}
void capture_ov(ov_log_level level, const char *message, void *) {
 // INFO can contain prompt details. Retain only failing-stage diagnostics.
 if (level >= OV_LOG_ERROR) { append_diagnostic(message); return; }
 if (!message) return;
 // Exact metadata prefixes audited in the pinned runtime; no user text.
 const char *safe[] = {"[Android-TTS]", "[TTS] Prompt:", "[TTS] Decode:",
                       "[TTS-Long] Single-shot path:", "[TTS-Long] Post-proc:",
                       "[Perf] Generate", "[Perf] CodecDecode"};
 for (const char *prefix : safe) if (strncmp(message,prefix,strlen(prefix)) == 0) {
  append_diagnostic(message); break;
 }
}
void capture_ggml(ggml_log_level level, const char *message, void *) {
 if (level == GGML_LOG_LEVEL_ERROR) append_diagnostic(message);
}
std::string failure(const char *stage, int status, const ov_audio *audio = nullptr) {
 std::ostringstream result;
 result << "OmniVoice " << stage << " failed (status=" << status;
 if (audio) result << ", rate=" << audio->sample_rate << ", channels=" << audio->channels
                   << ", samples=" << audio->n_samples << ", buffer=" << (audio->samples != nullptr);
 result << ")";
 // Upstream explicitly defines last_error as meaningful only after failure.
 if (status != OV_STATUS_OK) {
  const char *detail = ov_last_error();
  if (detail && *detail) result << ": " << std::string(detail, strnlen(detail, 1024));
 }
 std::lock_guard<std::mutex> lock(diagnostic_mutex);
 if (diagnostic_size) result << "; stages: " << diagnostics;
 return result.str();
}
}

extern "C" JNIEXPORT jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_omniVoice(JNIEnv *e,jobject,jbyteArray directory,jbyteArray text,jbyteArray language,jlong flag){
 try{
  auto path=media_string(e,directory),input=media_string(e,text),lang=media_string(e,language);void *cancel=reinterpret_cast<void *>(flag);
  if(!cancel)throw std::runtime_error("Missing cancellation");if(wt_abort(cancel))return nullptr;
  std::lock_guard<std::mutex> operation(operation_mutex);
  if(wt_abort(cancel))return nullptr;
  {std::lock_guard<std::mutex> lock(diagnostic_mutex);diagnostic_size=0;diagnostics[0]=0;}
  ov_log_set(capture_ov,nullptr);
  std::string model=path+"/omnivoice-base-Q8_0.gguf",codec=path+"/omnivoice-tokenizer-Q8_0.gguf";
  ov_init_params init;ov_init_default_params(&init);init.model_path=model.c_str();init.codec_path=codec.c_str();init.use_fa=false;
  std::unique_ptr<ov_context,decltype(&ov_free)> context(ov_init(&init),ov_free);if(!context)throw std::runtime_error(failure("model load",OV_STATUS_GENERATE_FAILED));if(wt_abort(cancel))return nullptr;
  // backend_init installs its own GGML callback during initialization. Replace
  // it afterward to retain kernel failures in the same bounded error report.
  ggml_log_set(capture_ggml,nullptr);
  ov_tts_params params;ov_tts_default_params(&params);params.chunk_duration_sec=5;params.chunk_threshold_sec=5;params.cancel=wt_abort;params.cancel_user_data=cancel;params.text=input.c_str();params.lang=lang.c_str();
  ov_audio audio={};struct Guard{ov_audio *p;~Guard(){ov_audio_free(p);}}guard{&audio};
  int status=ov_synthesize(context.get(),&params,&audio);if(status==OV_STATUS_CANCELLED||wt_abort(cancel))return nullptr;
  if(status!=OV_STATUS_OK||audio.sample_rate!=24000||audio.channels!=1||!audio.samples||audio.n_samples<1||audio.n_samples>24000*60)throw std::runtime_error(failure("synthesis",status,&audio));
  double energy=0;for(int i=0;i<audio.n_samples;i++){float v=audio.samples[i];if(!std::isfinite(v))throw std::runtime_error("Invalid OmniVoice PCM");energy+=v*v;}if(energy<=.001)throw std::runtime_error("OmniVoice returned silence");
  auto result=e->NewFloatArray(audio.n_samples);if(result)e->SetFloatArrayRegion(result,0,audio.n_samples,audio.samples);return result;
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
