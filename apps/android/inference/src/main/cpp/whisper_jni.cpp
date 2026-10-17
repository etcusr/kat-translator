#include "media_jni_util.h"
#include "whisper.h"
extern "C" {
#include "ASR/WhisperCancellation.h"
}
#include <memory>
#if defined(KAT_WHISPER_I8MM)
#define WHISPER_JNI(name) Java_org_openoffline_translator_inference_MediaNative_whisperI8mm##name
#elif defined(KAT_WHISPER_ARM82)
#define WHISPER_JNI(name) Java_org_openoffline_translator_inference_MediaNative_whisperArm82##name
#else
#define WHISPER_JNI(name) Java_org_openoffline_translator_inference_MediaNative_whisper##name
#endif
static jbyteArray whisper_run(JNIEnv *e,jlong handle,jfloatArray samples,jbyteArray language,jlong flag,bool words) {
 try {
  auto lang=media_string(e,language); auto pcm=media_samples(e,samples);
  auto *ctx=reinterpret_cast<whisper_context *>(handle);if(!ctx)throw std::runtime_error("Whisper model not loaded");
  auto *cancel=reinterpret_cast<wt_cancel_flag *>(flag); if(!cancel)throw std::runtime_error("Missing cancellation");
  if(lang!="auto"&&whisper_lang_id(lang.c_str())<0)throw std::runtime_error("Whisper does not support this language");
  if(wt_abort(cancel))return nullptr;
  if(wt_abort(cancel))return nullptr;
  auto params=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.translate=false;params.no_context=true;params.detect_language=false;params.language=lang.c_str();
  params.print_realtime=false;params.print_progress=false;params.print_timestamps=false;params.print_special=false;
  params.temperature=0;params.temperature_inc=0;params.n_threads=4;
  // The optional confirmation pass spells numbers, with the same constraints as Apple.
  if(words){params.suppress_regex=".*[0-9].*";params.no_timestamps=true;params.max_tokens=256;}
  params.abort_callback=[](void *p){return wt_abort(p);};params.abort_callback_user_data=cancel;
  int rc=whisper_full(ctx,params,pcm.data(),pcm.size());if(wt_abort(cancel))return nullptr;
  if(rc)throw std::runtime_error("Whisper inference failed");
  const char *detected=whisper_lang_str(whisper_full_lang_id(ctx));std::string output=detected?detected:lang;output+='\n';
  for(int i=0;i<whisper_full_n_segments(ctx);++i)output+=whisper_full_get_segment_text(ctx,i);
  return media_bytes(e,output);
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}

extern "C" JNIEXPORT jbyteArray JNICALL WHISPER_JNI(Run)(JNIEnv *e,jobject,jlong handle,jfloatArray samples,jbyteArray language,jlong flag) {
 return whisper_run(e,handle,samples,language,flag,false);
}
extern "C" JNIEXPORT jbyteArray JNICALL WHISPER_JNI(WordsRun)(JNIEnv *e,jobject,jlong handle,jfloatArray samples,jbyteArray language,jlong flag) {
 return whisper_run(e,handle,samples,language,flag,true);
}

// Each backend has distinct JNI names; handles must be freed by the library that created them.
extern "C" JNIEXPORT jlong JNICALL WHISPER_JNI(Create)(JNIEnv *e,jobject,jbyteArray path) {
 try {
  auto p=media_string(e,path);whisper_log_set([](ggml_log_level,const char *,void *){},nullptr);
  auto cp=whisper_context_default_params();cp.use_gpu=false;
  auto *ctx=whisper_init_from_file_with_params(p.c_str(),cp);
  if(!ctx)throw std::runtime_error("Whisper model could not be loaded");
  return reinterpret_cast<jlong>(ctx);
 }catch(const std::exception &ex){media_error(e,ex.what());return 0;}
}
extern "C" JNIEXPORT void JNICALL WHISPER_JNI(Free)(JNIEnv *,jobject,jlong handle) {
 if(handle)whisper_free(reinterpret_cast<whisper_context *>(handle));
}
// Full-lifetime compatibility entry point used by native boundary tests.
extern "C" JNIEXPORT jbyteArray JNICALL WHISPER_JNI()(JNIEnv *e,jobject obj,jbyteArray path,jfloatArray samples,jbyteArray language,jlong flag) {
 if(!flag){media_error(e,"Missing cancellation");return nullptr;}
 if(wt_abort(reinterpret_cast<wt_cancel_flag *>(flag)))return nullptr;
 auto handle=WHISPER_JNI(Create)(e,obj,path);if(!handle)return nullptr;
 auto result=WHISPER_JNI(Run)(e,obj,handle,samples,language,flag);
 WHISPER_JNI(Free)(e,obj,handle);return result;
}
