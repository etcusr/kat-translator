#include "media_jni_util.h"
extern "C" {
#include "Speech/SpeechRuntime.h"
#include "Camera/OCRRuntime.h"
int ot_ocr_run_scored(void *handle, const float *input, int width, int *ids, float *scores, int capacity);
}
#include <onnxruntime/onnxruntime_c_api.h>
#include <memory>
#include <algorithm>
#include <chrono>
#include <sys/auxv.h>
#include <asm/hwcap.h>
#define JNI(name) extern "C" JNIEXPORT
// This entry point stays baseline arm64. Check before loading any optimized code.
JNI(whisperArm82Supported) jboolean JNICALL Java_org_openoffline_translator_inference_MediaNative_whisperArm82Supported(JNIEnv *,jobject) {
 const auto caps=getauxval(AT_HWCAP);
 return (caps&HWCAP_ASIMDDP) && (caps&HWCAP_ASIMDHP) && (caps&HWCAP_FPHP);
}
JNI(whisperI8mmSupported) jboolean JNICALL Java_org_openoffline_translator_inference_MediaNative_whisperI8mmSupported(JNIEnv *,jobject) {
 const auto caps=getauxval(AT_HWCAP);
 return (caps&HWCAP_ASIMDDP) && (caps&HWCAP_ASIMDHP) && (caps&HWCAP_FPHP) && (getauxval(AT_HWCAP2)&HWCAP2_I8MM);
}
JNI(flagCreate) jlong JNICALL Java_org_openoffline_translator_inference_MediaNative_flagCreate(JNIEnv *,jobject){return reinterpret_cast<jlong>(wt_cancel_create());}
JNI(flagCancel) void JNICALL Java_org_openoffline_translator_inference_MediaNative_flagCancel(JNIEnv *,jobject,jlong f){wt_cancel_set(reinterpret_cast<wt_cancel_flag *>(f));}
JNI(flagFree) void JNICALL Java_org_openoffline_translator_inference_MediaNative_flagFree(JNIEnv *,jobject,jlong f){wt_cancel_free(reinterpret_cast<wt_cancel_flag *>(f));}
// Piper handles are owned and serialized by OfflineMedia. Callbacks finish before Run returns.
JNI(piperCreate) jlong JNICALL Java_org_openoffline_translator_inference_MediaNative_piperCreate(JNIEnv *e,jobject,jbyteArray model,jbyteArray tokens,jbyteArray data) {
 try {
  auto m=media_string(e,model),t=media_string(e,tokens),d=media_string(e,data);
  auto *engine=ot_tts_create(m.c_str(),t.c_str(),d.c_str());
  if(!engine)throw std::runtime_error("Offline voice could not be loaded");
  return reinterpret_cast<jlong>(engine);
 }catch(const std::exception &ex){media_error(e,ex.what());return 0;}
}
JNI(piperFree) void JNICALL Java_org_openoffline_translator_inference_MediaNative_piperFree(JNIEnv *,jobject,jlong handle) {
 if(handle)SherpaOnnxDestroyOfflineTts(reinterpret_cast<const SherpaOnnxOfflineTts *>(handle));
}
JNI(piperRun) jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_piperRun(JNIEnv *e,jobject,jlong handle,jbyteArray text,jlong flag,jintArray rate,jdoubleArray timing,jobject callback) {
 try {
  auto *engine=reinterpret_cast<const SherpaOnnxOfflineTts *>(handle);
  if(!engine || !flag || !rate || e->GetArrayLength(rate)<1 || !timing || e->GetArrayLength(timing)<4)throw std::runtime_error("Invalid speech outputs");
  auto s=media_string(e,text);void *f=reinterpret_cast<void *>(flag);if(wt_abort(f))return nullptr;
  const int sr=SherpaOnnxOfflineTtsSampleRate(engine);
  if(sr<8000 || sr>192000)throw std::runtime_error("Invalid speech sample rate");
  jmethodID method=nullptr;
  if(callback) { auto cls=e->GetObjectClass(callback);method=e->GetMethodID(cls,"onChunk","([FI)V");e->DeleteLocalRef(cls);if(!method)return nullptr; }
  struct State { JNIEnv *env;jobject callback;jmethodID method;void *flag;int rate;std::vector<float> delivered;bool invalid=false; } state{e,callback,method,f,sr,{}};
  const auto start=std::chrono::steady_clock::now();
  auto deliver=[](const float *samples,int32_t n,void *arg)->int32_t {
   auto &x=*static_cast<State *>(arg);
   if(wt_abort(x.flag) || x.env->ExceptionCheck() || x.invalid)return 0;
   if(n<0 || (n && !samples) || x.delivered.size()+n>size_t(x.rate)*60*30) { x.invalid=true;return 0; }
   if(!n)return 1;
   for(int i=0;i<n;i++)if(!std::isfinite(samples[i])){x.invalid=true;return 0;}
   // The aggregate is checked against the final native result in the same stochastic run.
   x.delivered.insert(x.delivered.end(),samples,samples+n);
   if(x.callback) {
    auto array=x.env->NewFloatArray(n);if(!array)return 0;
    x.env->SetFloatArrayRegion(array,0,n,samples);
    if(!x.env->ExceptionCheck())x.env->CallVoidMethod(x.callback,x.method,array,x.rate);
    x.env->DeleteLocalRef(array);
   }
   return !wt_abort(x.flag) && !x.env->ExceptionCheck();
  };
  std::unique_ptr<const SherpaOnnxGeneratedAudio,decltype(&SherpaOnnxDestroyOfflineTtsGeneratedAudio)> audio(
   SherpaOnnxOfflineTtsGenerateWithCallbackWithArg(engine,s.c_str(),0,1.0f,deliver,&state),SherpaOnnxDestroyOfflineTtsGeneratedAudio);
  if(e->ExceptionCheck() || wt_abort(f))return nullptr;
  auto generated=std::chrono::steady_clock::now();
  if(state.invalid || !audio || audio->n<1 || audio->sample_rate!=sr || state.delivered.size()!=size_t(audio->n) ||
     !std::equal(state.delivered.begin(),state.delivered.end(),audio->samples))throw std::runtime_error("Incomplete speech stream");
  auto result=e->NewFloatArray(audio->n);if(!result)return nullptr;
  e->SetFloatArrayRegion(result,0,audio->n,audio->samples);if(e->ExceptionCheck())return nullptr;
  jint sampleRate=sr;e->SetIntArrayRegion(rate,0,1,&sampleRate);
  jdouble times[4]{0,std::chrono::duration<double>(generated-start).count(),std::chrono::duration<double>(std::chrono::steady_clock::now()-generated).count(),0};
  e->SetDoubleArrayRegion(timing,0,4,times);return result;
 }catch(const std::exception &ex){if(!e->ExceptionCheck())media_error(e,ex.what());return nullptr;}
}
JNI(tts) jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_tts(JNIEnv *e,jobject,jbyteArray model,jbyteArray tokens,jbyteArray data,jbyteArray text,jbyteArray language,jboolean supertonic,jlong flag,jintArray rate,jdoubleArray timing){
 try{
  if(!rate||e->GetArrayLength(rate)<1||!timing||e->GetArrayLength(timing)<4)throw std::runtime_error("Invalid speech outputs");
  using Clock=std::chrono::steady_clock;auto phase=Clock::now();
  auto elapsed=[&](){auto now=Clock::now();double seconds=std::chrono::duration<double>(now-phase).count();phase=now;return seconds;};
  jdouble times[4]{};
  auto m=media_string(e,model),t=media_string(e,tokens),d=media_string(e,data),s=media_string(e,text),l=media_string(e,language);
  void *f=reinterpret_cast<void *>(flag);if(wt_abort(f))return nullptr;
  std::unique_ptr<const SherpaOnnxOfflineTts,decltype(&SherpaOnnxDestroyOfflineTts)> engine(supertonic?ot_supertonic_create(m.c_str()):ot_tts_create(m.c_str(),t.c_str(),d.c_str()),SherpaOnnxDestroyOfflineTts);
  if(!engine)throw std::runtime_error("Offline voice could not be loaded");
  times[0]=elapsed();
  std::unique_ptr<const SherpaOnnxGeneratedAudio,decltype(&SherpaOnnxDestroyOfflineTtsGeneratedAudio)> audio(supertonic?ot_supertonic_generate(engine.get(),s.c_str(),l.c_str(),f):ot_tts_generate(engine.get(),s.c_str(),f),SherpaOnnxDestroyOfflineTtsGeneratedAudio);
  if(wt_abort(f))return nullptr;
  times[1]=elapsed();
  if(!audio||audio->n<1||audio->sample_rate<8000||audio->sample_rate>192000||audio->n>audio->sample_rate*60*30)throw std::runtime_error("Offline voice returned invalid PCM");
  for(int i=0;i<audio->n;i++)if(!std::isfinite(audio->samples[i]))throw std::runtime_error("Nonfinite voice PCM");
  auto result=e->NewFloatArray(audio->n);if(!result)return nullptr;
  e->SetFloatArrayRegion(result,0,audio->n,audio->samples);if(e->ExceptionCheck())return nullptr;
  jint sr=audio->sample_rate;e->SetIntArrayRegion(rate,0,1,&sr);if(e->ExceptionCheck())return nullptr;
  times[2]=elapsed();audio.reset();engine.reset();times[3]=elapsed();e->SetDoubleArrayRegion(timing,0,4,times);return result;
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
JNI(omni) jbyteArray JNICALL Java_org_openoffline_translator_inference_MediaNative_omni(JNIEnv *e,jobject,jbyteArray model,jbyteArray tokens,jfloatArray samples,jlong flag){
 try{
 auto m=media_string(e,model),t=media_string(e,tokens);auto pcm=media_samples(e,samples);void *f=reinterpret_cast<void *>(flag);if(wt_abort(f))return nullptr;
 std::unique_ptr<const SherpaOnnxOfflineRecognizer,decltype(&SherpaOnnxDestroyOfflineRecognizer)> engine(ot_omni_create(m.c_str(),t.c_str()),SherpaOnnxDestroyOfflineRecognizer);if(!engine)throw std::runtime_error("Omnilingual model could not be loaded");
 std::unique_ptr<const SherpaOnnxOfflineStream,decltype(&SherpaOnnxDestroyOfflineStream)> stream(SherpaOnnxCreateOfflineStream(engine.get()),SherpaOnnxDestroyOfflineStream);if(!stream)throw std::runtime_error("Omnilingual stream failed");
 SherpaOnnxAcceptWaveformOffline(stream.get(),16000,pcm.data(),pcm.size());if(wt_abort(f))return nullptr;SherpaOnnxDecodeOfflineStream(engine.get(),stream.get());if(wt_abort(f))return nullptr;
 std::unique_ptr<const SherpaOnnxOfflineRecognizerResult,decltype(&SherpaOnnxDestroyOfflineRecognizerResult)> result(SherpaOnnxGetOfflineStreamResult(stream.get()),SherpaOnnxDestroyOfflineRecognizerResult);if(!result)throw std::runtime_error("Omnilingual inference failed");return media_bytes(e,result->text?result->text:"");
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
JNI(nemoCreate) jlong JNICALL Java_org_openoffline_translator_inference_MediaNative_nemoCreate(JNIEnv *e,jobject,jbyteArray directory,jboolean parakeet){
 try {
  auto d=media_string(e,directory),enc=d+"/encoder.int8.onnx",dec=d+"/decoder.onnx",join=d+"/joiner.onnx",tokens=d+"/tokens.txt";
  if(parakeet){dec=d+"/decoder.int8.onnx";join=d+"/joiner.int8.onnx";}
  SherpaOnnxOfflineRecognizerConfig c{};c.feat_config.sample_rate=16000;c.feat_config.feature_dim=80;
  c.model_config.transducer.encoder=enc.c_str();c.model_config.transducer.decoder=dec.c_str();c.model_config.transducer.joiner=join.c_str();
  c.model_config.tokens=tokens.c_str();c.model_config.num_threads=2;c.model_config.provider="cpu";c.model_config.model_type="nemo_transducer";c.decoding_method="greedy_search";
  auto *engine=SherpaOnnxCreateOfflineRecognizer(&c);if(!engine)throw std::runtime_error("Speech recognition model could not be loaded");
  return reinterpret_cast<jlong>(engine);
 }catch(const std::exception &ex){media_error(e,ex.what());return 0;}
}
JNI(nemoFree) void JNICALL Java_org_openoffline_translator_inference_MediaNative_nemoFree(JNIEnv *,jobject,jlong handle){if(handle)SherpaOnnxDestroyOfflineRecognizer(reinterpret_cast<const SherpaOnnxOfflineRecognizer *>(handle));}
JNI(nemoRun) jbyteArray JNICALL Java_org_openoffline_translator_inference_MediaNative_nemoRun(JNIEnv *e,jobject,jlong handle,jfloatArray samples,jlong flag){
 try {
  auto *engine=reinterpret_cast<const SherpaOnnxOfflineRecognizer *>(handle);if(!engine)throw std::runtime_error("ASR model not loaded");
  auto pcm=media_samples(e,samples);if(pcm.size()>30*16000)throw std::runtime_error("ASR segment exceeds 30 seconds");
  void *f=reinterpret_cast<void *>(flag);if(wt_abort(f))return nullptr;
  std::unique_ptr<const SherpaOnnxOfflineStream,decltype(&SherpaOnnxDestroyOfflineStream)> stream(SherpaOnnxCreateOfflineStream(engine),SherpaOnnxDestroyOfflineStream);
  if(!stream)throw std::runtime_error("ASR stream failed");
  SherpaOnnxAcceptWaveformOffline(stream.get(),16000,pcm.data(),pcm.size());SherpaOnnxDecodeOfflineStream(engine,stream.get());if(wt_abort(f))return nullptr;
  std::unique_ptr<const SherpaOnnxOfflineRecognizerResult,decltype(&SherpaOnnxDestroyOfflineRecognizerResult)> result(SherpaOnnxGetOfflineStreamResult(stream.get()),SherpaOnnxDestroyOfflineRecognizerResult);
  if(!result)throw std::runtime_error("ASR inference failed");return media_bytes(e,result->text?result->text:"");
 }catch(const std::exception &ex){media_error(e,ex.what());return nullptr;}
}
JNI(ocrLoad) jlong JNICALL Java_org_openoffline_translator_inference_MediaNative_ocrLoad(JNIEnv *e,jobject,jbyteArray path){try{return reinterpret_cast<jlong>(ot_ocr_load(media_string(e,path).c_str()));}catch(const std::exception &ex){media_error(e,ex.what());return 0;}}
JNI(ocrFree) void JNICALL Java_org_openoffline_translator_inference_MediaNative_ocrFree(JNIEnv *,jobject,jlong h){ot_ocr_free(reinterpret_cast<void *>(h));}
JNI(ocrHeight) jint JNICALL Java_org_openoffline_translator_inference_MediaNative_ocrHeight(JNIEnv *,jobject,jlong h){return ot_ocr_height(reinterpret_cast<void *>(h));}
JNI(ocrRun) jintArray JNICALL Java_org_openoffline_translator_inference_MediaNative_ocrRun(JNIEnv *e,jobject,jlong h,jfloatArray input,jint width){
 auto *ctx=reinterpret_cast<void *>(h);int height=ot_ocr_height(ctx);if(width<8||width>4096||height<16||e->GetArrayLength(input)!=3*width*height){media_error(e,"Invalid OCR input");return nullptr;}
 std::vector<float> v(3*width*height);e->GetFloatArrayRegion(input,0,v.size(),v.data());int ids[4096];int n=ot_ocr_run(ctx,v.data(),width,ids,4096);if(n<1){media_error(e,"OCR inference failed");return nullptr;}auto a=e->NewIntArray(n);if(a)e->SetIntArrayRegion(a,0,n,ids);return a;
}
// Interleaved CTC class id / maximum probability. Blank scores are not confidence evidence.
JNI(ocrRunScored) jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_ocrRunScored(JNIEnv *e,jobject,jlong h,jfloatArray input,jint width){
 auto *ctx=reinterpret_cast<void *>(h);int height=ot_ocr_height(ctx);if(width<8||width>4096||height<16||e->GetArrayLength(input)!=3*width*height){media_error(e,"Invalid OCR input");return nullptr;}
 std::vector<float> v(3*width*height);e->GetFloatArrayRegion(input,0,v.size(),v.data());int ids[4096];float scores[4096];
 int n=ot_ocr_run_scored(ctx,v.data(),width,ids,scores,4096);if(n<1){media_error(e,"OCR confidence inference failed");return nullptr;}
 std::vector<float> pairs(2*n);for(int i=0;i<n;i++){pairs[2*i]=ids[i];pairs[2*i+1]=scores[i];}
 auto a=e->NewFloatArray(pairs.size());if(a)e->SetFloatArrayRegion(a,0,pairs.size(),pairs.data());return a;
}
// Detector uses the ORT API17 ABI, same as the shared recognizer. No network provider.
JNI(detect) jfloatArray JNICALL Java_org_openoffline_translator_inference_MediaNative_detect(JNIEnv *e,jobject,jbyteArray path,jfloatArray input,jint width,jint height){
 const OrtApi *api=OrtGetApiBase()->GetApi(17);OrtEnv *env=nullptr;OrtSessionOptions *options=nullptr;OrtSession *session=nullptr;OrtMemoryInfo *memory=nullptr;OrtValue *in=nullptr,*out=nullptr;OrtAllocator *alloc=nullptr;char *iname=nullptr,*oname=nullptr;OrtTensorTypeAndShapeInfo *shape=nullptr;jfloatArray result=nullptr;
 auto check=[&](OrtStatus *s){if(s){std::string msg=api->GetErrorMessage(s);api->ReleaseStatus(s);throw std::runtime_error(msg);}};
 try{
 if(!api||width<32||height<32||width>1536||height>1536||width%32||height%32||e->GetArrayLength(input)!=3*width*height)throw std::runtime_error("Invalid detector input");
 auto p=media_string(e,path);std::vector<float> values(3*width*height);e->GetFloatArrayRegion(input,0,values.size(),values.data());
 check(api->CreateEnv(ORT_LOGGING_LEVEL_FATAL,"kat-ocr",&env));check(api->DisableTelemetryEvents(env));check(api->CreateSessionOptions(&options));check(api->SetIntraOpNumThreads(options,2));check(api->DisableCpuMemArena(options));check(api->CreateSession(env,p.c_str(),options,&session));
 check(api->GetAllocatorWithDefaultOptions(&alloc));check(api->SessionGetInputName(session,0,alloc,&iname));check(api->SessionGetOutputName(session,0,alloc,&oname));check(api->CreateCpuMemoryInfo(OrtArenaAllocator,OrtMemTypeDefault,&memory));int64_t dims[]={1,3,height,width};check(api->CreateTensorWithDataAsOrtValue(memory,values.data(),values.size()*sizeof(float),dims,4,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,&in));
 const OrtValue *inputs[]={in};const char *names[]={iname},*outputs[]={oname};check(api->Run(session,nullptr,names,inputs,1,outputs,1,&out));check(api->GetTensorTypeAndShape(out,&shape));size_t rank=0;check(api->GetDimensionsCount(shape,&rank));int64_t sizes[4];if(rank!=4)throw std::runtime_error("Unexpected detector output rank");check(api->GetDimensions(shape,sizes,4));ONNXTensorElementDataType type;check(api->GetTensorElementType(shape,&type));if(type!=ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT||sizes[0]!=1||sizes[1]!=1||sizes[2]!=height||sizes[3]!=width)throw std::runtime_error("Unexpected detector output dimensions");
 float *v=nullptr;check(api->GetTensorMutableData(out,reinterpret_cast<void **>(&v)));for(int i=0;i<width*height;i++)if(!std::isfinite(v[i]))throw std::runtime_error("Nonfinite detector output");result=e->NewFloatArray(width*height);if(result)e->SetFloatArrayRegion(result,0,width*height,v);
 }catch(const std::exception &ex){media_error(e,ex.what());}
 if(shape)api->ReleaseTensorTypeAndShapeInfo(shape);if(out)api->ReleaseValue(out);if(in)api->ReleaseValue(in);if(memory)api->ReleaseMemoryInfo(memory);if(iname)alloc->Free(alloc,iname);if(oname)alloc->Free(alloc,oname);if(session)api->ReleaseSession(session);if(options)api->ReleaseSessionOptions(options);if(env)api->ReleaseEnv(env);return result;
}
JNI(vadCreate) jlong JNICALL Java_org_openoffline_translator_inference_MediaNative_vadCreate(JNIEnv *e,jobject,jbyteArray path){try{return reinterpret_cast<jlong>(ot_vad_create(media_string(e,path).c_str()));}catch(const std::exception &ex){media_error(e,ex.what());return 0;}}
JNI(vadFree) void JNICALL Java_org_openoffline_translator_inference_MediaNative_vadFree(JNIEnv *,jobject,jlong handle){if(handle)SherpaOnnxDestroyVoiceActivityDetector(reinterpret_cast<const SherpaOnnxVoiceActivityDetector *>(handle));}
JNI(vadAccept) jboolean JNICALL Java_org_openoffline_translator_inference_MediaNative_vadAccept(JNIEnv *e,jobject,jlong handle,jfloatArray samples){
 try{if(!handle)throw std::runtime_error("VAD not loaded");auto pcm=media_samples(e,samples);auto *vad=reinterpret_cast<const SherpaOnnxVoiceActivityDetector *>(handle);SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad,pcm.data(),pcm.size());bool speech=SherpaOnnxVoiceActivityDetectorDetected(vad)||!SherpaOnnxVoiceActivityDetectorEmpty(vad);while(!SherpaOnnxVoiceActivityDetectorEmpty(vad))SherpaOnnxVoiceActivityDetectorPop(vad);return speech;}catch(const std::exception &ex){media_error(e,ex.what());return false;}
}
