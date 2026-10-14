#include "media_jni_util.h"
extern "C" {
#include "Speech/WayuSpeechRuntime.h"
#include "ASR/WhisperCancellation.h"
int kat_wayu_init(const char *root);
const char *kat_wayu_error(void);
int kat_wayu_tokens(const char *text,int64_t *tokens,int capacity);
int kat_wayu_style(const char *path,const char *voice,int length,float *style);
}
#include <memory>
extern "C" JNIEXPORT jlongArray JNICALL Java_org_openoffline_translator_inference_MediaNative_wayuTokens(JNIEnv *e,jobject,jbyteArray runtime,jbyteArray text){
 try{auto root=media_string(e,runtime),input=media_string(e,text);if(!kat_wayu_init(root.c_str()))throw std::runtime_error(std::string("Wayu Python frontend initialization failed: ")+kat_wayu_error());int64_t tokens[512];int n=kat_wayu_tokens(input.c_str(),tokens,512);if(n<=2)throw std::runtime_error(n==-2?"Wayu speech fragment is too long":"Wayu cannot pronounce this text without dropping words");auto a=e->NewLongArray(n);if(a)e->SetLongArrayRegion(a,0,n,reinterpret_cast<const jlong *>(tokens));return a;}catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
extern "C" JNIEXPORT jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_wayu(JNIEnv *e,jobject,jbyteArray runtime,jbyteArray directory,jbyteArray text,jbyteArray voice,jlong flag){
 try{
  auto root=media_string(e,runtime),path=media_string(e,directory),input=media_string(e,text),v=media_string(e,voice);void *cancel=reinterpret_cast<void *>(flag);if(!cancel)throw std::runtime_error("Missing cancellation");if(wt_abort(cancel))return nullptr;
  if(!kat_wayu_init(root.c_str()))throw std::runtime_error(std::string("Wayu Python frontend initialization failed: ")+kat_wayu_error());int64_t tokens[512];int n=kat_wayu_tokens(input.c_str(),tokens,512);if(n<=2)throw std::runtime_error(n==-2?"Wayu speech fragment is too long":"Wayu cannot pronounce this text without dropping words");if(wt_abort(cancel))return nullptr;
  float style[256];if(!kat_wayu_style((path+"/wayu-styles.bin").c_str(),v.c_str(),n-2,style))throw std::runtime_error("Wayu voice style could not be loaded");
  std::unique_ptr<void,decltype(&ot_wayu_free)> context(ot_wayu_load((path+"/wayu-prosody.bin").c_str(),(path+"/wayu-curves.bin").c_str(),(path+"/wayu-decoder.bin").c_str()),ot_wayu_free);if(!context)throw std::runtime_error("Wayu model could not be loaded");if(wt_abort(cancel))return nullptr;
  int count=0;std::unique_ptr<float,decltype(&ot_wayu_audio_free)> audio(ot_wayu_generate(context.get(),tokens,n,style,&count,cancel),ot_wayu_audio_free);if(wt_abort(cancel))return nullptr;
  if(!audio||count<1||count>24000*60)throw std::runtime_error("Wayu synthesis failed");double energy=0;for(int i=0;i<count;i++){float x=audio.get()[i];if(!std::isfinite(x))throw std::runtime_error("Invalid Wayu PCM");energy+=x*x;}if(energy<=.001)throw std::runtime_error("Wayu returned silence");
  auto a=e->NewFloatArray(count);if(a)e->SetFloatArrayRegion(a,0,count,audio.get());return a;
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
