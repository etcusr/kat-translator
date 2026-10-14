#pragma once
#include <jni.h>
#include <string>
#include <stdexcept>
#include <atomic>
#include <vector>
#include <cmath>
inline std::string media_string(JNIEnv *e,jbyteArray a) {
 if(!a) throw std::runtime_error("Missing UTF-8 input");
 std::string s(e->GetArrayLength(a), '\0'); e->GetByteArrayRegion(a,0,s.size(),reinterpret_cast<jbyte *>(s.data()));
 if(s.find('\0')!=std::string::npos) throw std::runtime_error("NUL is not supported"); return s;
}
inline jbyteArray media_bytes(JNIEnv *e,const std::string &s) {
 auto a=e->NewByteArray(s.size()); if(a)e->SetByteArrayRegion(a,0,s.size(),reinterpret_cast<const jbyte *>(s.data())); return a;
}
inline void media_error(JNIEnv *e,const char *s) { if(!e->ExceptionCheck()) e->ThrowNew(e->FindClass("java/lang/IllegalStateException"),s); }
inline std::vector<float> media_samples(JNIEnv *e,jfloatArray a) {
 if(!a) throw std::runtime_error("Missing audio");
 int n=e->GetArrayLength(a); if(n<1||n>16000*60*30)throw std::runtime_error("Audio must contain 1 sample to 30 minutes");
 std::vector<float> v(n); e->GetFloatArrayRegion(a,0,n,v.data()); for(float f:v)if(!std::isfinite(f))throw std::runtime_error("Invalid PCM"); return v;
}
