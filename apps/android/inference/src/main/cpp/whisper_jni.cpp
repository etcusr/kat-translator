#include "media_jni_util.h"
#include "whisper.h"
extern "C" {
#include "ASR/WhisperCancellation.h"
}
#include <memory>
extern "C" JNIEXPORT jbyteArray JNICALL Java_org_openoffline_translator_inference_MediaNative_whisper(JNIEnv *e,jobject,jbyteArray path,jfloatArray samples,jbyteArray language,jlong flag) {
 try {
  auto p=media_string(e,path), lang=media_string(e,language); auto pcm=media_samples(e,samples);
  auto *cancel=reinterpret_cast<wt_cancel_flag *>(flag); if(!cancel)throw std::runtime_error("Missing cancellation");
  if(lang!="auto"&&whisper_lang_id(lang.c_str())<0)throw std::runtime_error("Whisper does not support this language");
  if(wt_abort(cancel))return nullptr;
  whisper_log_set([](ggml_log_level,const char *,void *){},nullptr);
  auto cp=whisper_context_default_params(); cp.use_gpu=false;
  std::unique_ptr<whisper_context,decltype(&whisper_free)> ctx(whisper_init_from_file_with_params(p.c_str(),cp),whisper_free);
  if(!ctx)throw std::runtime_error("Whisper model could not be loaded");
  if(wt_abort(cancel))return nullptr;
  auto params=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.translate=false;params.no_context=true;params.detect_language=false;params.language=lang.c_str();
  params.print_realtime=false;params.print_progress=false;params.print_timestamps=false;params.print_special=false;
  params.temperature=0;params.temperature_inc=0;params.n_threads=4;
  params.abort_callback=[](void *p){return wt_abort(p);};params.abort_callback_user_data=cancel;
  int rc=whisper_full(ctx.get(),params,pcm.data(),pcm.size());if(wt_abort(cancel))return nullptr;
  if(rc)throw std::runtime_error("Whisper inference failed");
  const char *detected=whisper_lang_str(whisper_full_lang_id(ctx.get()));std::string output=detected?detected:lang;output+='\n';
  for(int i=0;i<whisper_full_n_segments(ctx.get());++i)output+=whisper_full_get_segment_text(ctx.get(),i);
  return media_bytes(e,output);
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
