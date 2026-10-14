#include <jni.h>
#include <string>
#include <stdexcept>
#include <vector>
#include "OpusRuntime.h"

#define JNI(name) Java_org_openoffline_translator_inference_OpusNative_##name
namespace {
void *pointer(jlong value) { return reinterpret_cast<void *>(value); }
std::string bytes(JNIEnv *env, jbyteArray array) {
    if (!array) throw std::invalid_argument("Missing UTF-8 value");
    const auto size = env->GetArrayLength(array);
    std::string result(size, '\0');
    env->GetByteArrayRegion(array, 0, size, reinterpret_cast<jbyte *>(result.data()));
    if (result.find('\0') != std::string::npos) throw std::invalid_argument("Embedded NUL is not supported");
    return result;
}
void error(JNIEnv *env, const char *message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}
}

extern "C" JNIEXPORT jlong JNICALL JNI(load)(JNIEnv *env, jobject, jbyteArray path) {
    try {
        const auto value = bytes(env, path);
        auto *context = ot_opus_load(value.c_str());
        if (!context) error(env, ot_opus_last_error());
        return reinterpret_cast<jlong>(context);
    } catch (const std::exception& exception) { error(env, exception.what()); return 0; }
    catch (...) { error(env, "OPUS package could not be opened"); return 0; }
}
extern "C" JNIEXPORT void JNICALL JNI(free)(JNIEnv *, jobject, jlong handle) { ot_opus_free(pointer(handle)); }
extern "C" JNIEXPORT jlong JNICALL JNI(flagCreate)(JNIEnv *, jobject) { return reinterpret_cast<jlong>(ot_opus_flag_create()); }
extern "C" JNIEXPORT void JNICALL JNI(flagCancel)(JNIEnv *, jobject, jlong flag) { ot_opus_flag_cancel(pointer(flag)); }
extern "C" JNIEXPORT void JNICALL JNI(flagFree)(JNIEnv *, jobject, jlong flag) { ot_opus_flag_free(pointer(flag)); }

extern "C" JNIEXPORT jint JNICALL JNI(count)(JNIEnv *env, jobject, jlong handle, jbyteArray text, jbyteArray direction, jbyteArray marker) {
    try {
        if (!handle) throw std::invalid_argument("OPUS is closed");
        const auto value = bytes(env, text), name = bytes(env, direction), label = bytes(env, marker);
        const auto count = ot_opus_count_direction(pointer(handle), value.c_str(), name.c_str(), label.c_str());
        if (count < 0) error(env, "OPUS tokenization failed");
        return count;
    } catch (const std::exception& exception) { error(env, exception.what()); return -1; }
    catch (...) { error(env, "OPUS tokenization failed"); return -1; }
}

extern "C" JNIEXPORT jbyteArray JNICALL JNI(run)(JNIEnv *env, jobject, jlong handle, jbyteArray text, jbyteArray direction, jbyteArray marker, jlong flag, jintArray status) {
    try {
        if (!handle || !flag || !status || env->GetArrayLength(status) != 1) throw std::invalid_argument("Invalid OPUS invocation");
        const auto value = bytes(env, text), name = bytes(env, direction), label = bytes(env, marker);
        std::vector<char> output(65536);
        const jint result = ot_opus_run_direction(pointer(handle), value.c_str(), name.c_str(), label.c_str(), pointer(flag), output.data(), output.size());
        env->SetIntArrayRegion(status, 0, 1, &result);
        const auto size = result == 0 ? std::char_traits<char>::length(output.data()) : 0;
        auto array = env->NewByteArray(static_cast<jsize>(size));
        if (array) env->SetByteArrayRegion(array, 0, static_cast<jsize>(size), reinterpret_cast<jbyte *>(output.data()));
        return array;
    } catch (const std::exception& exception) { error(env, exception.what()); return nullptr; }
    catch (...) { error(env, "OPUS translation failed"); return nullptr; }
}

extern "C" JNIEXPORT jint JNICALL JNI(prepare)(JNIEnv *env, jobject, jlong handle, jbyteArray direction, jlong flag) {
    try {
        if (!handle || !flag) throw std::invalid_argument("Invalid OPUS preparation");
        const auto name = bytes(env, direction);
        return ot_opus_prepare_direction(pointer(handle), name.c_str(), pointer(flag));
    } catch (const std::exception& exception) { error(env, exception.what()); return -1; }
    catch (...) { error(env, "OPUS preparation failed"); return -1; }
}
