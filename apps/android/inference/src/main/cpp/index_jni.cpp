#include <jni.h>
#include <string>
#include <vector>
#include <stdexcept>
#include "TranslationRuntime.h"
#include "index_mtp.h"
#include <memory>
#include "ggml-backend.h"
#include <sys/auxv.h>
#include <asm/hwcap.h>
#define JNI(name) Java_org_openoffline_translator_inference_NativeBridge_##name
static void *ptr(jlong v) { return reinterpret_cast<void *>(v); }
struct EngineHandle {
    void *value=nullptr;
    bool mtp=false;
    ~EngineHandle() { if(mtp)kat_mtp_free(value);else ot_mt_free(value); }
    int tokens(const char *p,const char *t,const char *s,int *out,size_t capacity) {
        return mtp?kat_mtp_tokens(value,p,t,s,out,capacity):ot_mt_tokens(value,p,t,s,out,capacity);
    }
};
static std::string bytes(JNIEnv *e,jbyteArray a) {
    if (!a) throw std::invalid_argument("Null UTF-8 array");
    auto n=e->GetArrayLength(a);std::string value(n,'\0');
    e->GetByteArrayRegion(a,0,n,reinterpret_cast<jbyte *>(value.data()));
    if(value.find('\0')!=std::string::npos)throw std::invalid_argument("NUL is not supported");
    return value;
}
static void error(JNIEnv *e,const char *message) { e->ThrowNew(e->FindClass("java/lang/IllegalArgumentException"),message); }
// ggml CPU code is compiled for armv8.2-a+dotprod+fp16 (CMakeLists.txt). Refuse
// older cores before any ggml code runs instead of failing with SIGILL.
static bool cpu_supported() {
    auto caps=getauxval(AT_HWCAP);
    return (caps&HWCAP_ASIMDDP) && (caps&HWCAP_ASIMDHP) && (caps&HWCAP_FPHP);
}
static ggml_backend_dev_t gpu_device() {
    if(!cpu_supported())return nullptr;
    auto device=ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
    return device?device:ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);
}
extern "C" JNIEXPORT jstring JNICALL JNI(gpuName)(JNIEnv *e,jobject) {
    auto device=gpu_device();
    return e->NewStringUTF(device?ggml_backend_dev_description(device):"");
}
extern "C" double kat_read_bandwidth_gbps(int threads, size_t bytes_per_thread, double seconds);
extern "C" JNIEXPORT jdouble JNICALL JNI(readBandwidth)(JNIEnv *,jobject,jint threads,jint megabytes,jdouble seconds) {
    try { return kat_read_bandwidth_gbps(threads,static_cast<size_t>(megabytes)<<20,seconds); } catch (...) { return -1; }
}
extern "C" double kat_gpu_matvec_gbps(ggml_backend_dev_t device, double seconds);
extern "C" JNIEXPORT jdouble JNICALL JNI(gpuMatvecBandwidth)(JNIEnv *,jobject,jdouble seconds) {
    try { return kat_gpu_matvec_gbps(gpu_device(),seconds); } catch (...) { return -1; }
}
extern "C" JNIEXPORT jlong JNICALL JNI(load)(JNIEnv *e,jobject,jbyteArray path,jint threads,jboolean gpu,jboolean flash,jboolean mtp) {
    try {
        if(!cpu_supported()) { error(e,"This processor lacks ARMv8.2 dot-product/FP16 instructions required by Index");return 0; }
        if(gpu && !gpu_device()) { error(e,"Vulkan GPU is unavailable");return 0; }
        if(mtp && !gpu) { error(e,"MTP requires GPU");return 0; }
        auto p=bytes(e,path);auto h=std::make_unique<EngineHandle>();h->mtp=mtp;
        h->value=mtp?kat_mtp_load(p.c_str(),threads,flash):ot_mt_load_config(p.c_str(),threads,gpu?99:0,flash?1:0);
        return h->value?reinterpret_cast<jlong>(h.release()):0;
    }
    catch (...) { error(e,"Invalid model path");return 0; }
}
extern "C" JNIEXPORT void JNICALL JNI(free)(JNIEnv *,jobject,jlong h) { delete static_cast<EngineHandle *>(ptr(h)); }
extern "C" JNIEXPORT jlong JNICALL JNI(flagCreate)(JNIEnv *,jobject) { return reinterpret_cast<jlong>(ot_mt_flag_create()); }
extern "C" JNIEXPORT void JNICALL JNI(flagCancel)(JNIEnv *,jobject,jlong f) { ot_mt_flag_cancel(ptr(f)); }
extern "C" JNIEXPORT void JNICALL JNI(flagFree)(JNIEnv *,jobject,jlong f) { ot_mt_flag_free(ptr(f)); }
extern "C" JNIEXPORT jintArray JNICALL JNI(tokens)(JNIEnv *e,jobject,jlong h,jbyteArray p,jbyteArray t,jbyteArray s) {
    try {
        auto prefix=bytes(e,p),text=bytes(e,t),suffix=bytes(e,s);
        auto *handle=static_cast<EngineHandle *>(ptr(h));
        int count=handle->tokens(prefix.c_str(),text.c_str(),suffix.c_str(),nullptr,0);
        if(count<0)throw std::runtime_error("Tokenizer failure");
        std::vector<int> values(count);
        if(handle->tokens(prefix.c_str(),text.c_str(),suffix.c_str(),values.data(),count)!=count)throw std::runtime_error("Tokenizer changed");
        auto result=e->NewIntArray(count);if(result)e->SetIntArrayRegion(result,0,count,values.data());return result;
    } catch (...) { error(e,"Tokenizer failure");return nullptr; }
}
extern "C" JNIEXPORT jbyteArray JNICALL JNI(run)(JNIEnv *e,jobject,jlong h,jbyteArray p,jbyteArray t,jbyteArray s,jlong f,jint capacity,jdoubleArray stats) {
    try {
        if(capacity<1 || capacity>65536 || !stats || e->GetArrayLength(stats)!=4)throw std::invalid_argument("Invalid stats");
        auto prefix=bytes(e,p),text=bytes(e,t),suffix=bytes(e,s);
        std::vector<char> output(capacity);double first=-1;
        auto *handle=static_cast<EngineHandle *>(ptr(h));int drafted=0,accepted=0;
        int status=handle->mtp?kat_mtp_run(handle->value,prefix.c_str(),text.c_str(),suffix.c_str(),ptr(f),output.data(),output.size(),&first,&drafted,&accepted):ot_mt_run(handle->value,prefix.c_str(),text.c_str(),suffix.c_str(),ptr(f),output.data(),output.size(),&first);
        double values[]={static_cast<double>(status),first,static_cast<double>(drafted),static_cast<double>(accepted)};e->SetDoubleArrayRegion(stats,0,4,values);
        size_t n=status==0?std::char_traits<char>::length(output.data()):0;
        auto result=e->NewByteArray(static_cast<jsize>(n));if(result)e->SetByteArrayRegion(result,0,n,reinterpret_cast<jbyte *>(output.data()));return result;
    } catch (...) { error(e,"Native inference failure");return nullptr; }
}
extern "C" JNIEXPORT jbyteArray JNICALL JNI(echo)(JNIEnv *e,jobject,jbyteArray value) {
    try {auto v=bytes(e,value);auto out=e->NewByteArray(v.size());if(out)e->SetByteArrayRegion(out,0,v.size(),reinterpret_cast<const jbyte *>(v.data()));return out;}
    catch (...) {error(e,"Invalid UTF-8 input");return nullptr;}
}
