#include "SpeechRuntime.h"
#include <stdio.h>
#include <math.h>
#include <time.h>
// Exercise Supertonic and Chinese through the same bridge as iOS; Thai uses thai-voice-probe.py.
int main(void) {
    const char *codes[] = {"ru","en","es","fr","de","it","pt","ja","ko","ar","tr","hi","zh"};
    const char *texts[] = {
        "Здравствуйте! Так звучит мой голос. Поезд отправляется в пять часов.",
        "Hello! This is a sample of my voice. The train leaves at five.",
        "¡Hola! Así suena mi voz. El tren sale a las cinco.",
        "Bonjour ! Voici ma voix. Le train part à cinq heures.",
        "Hallo! So klingt meine Stimme. Der Zug fährt um fünf Uhr ab.",
        "Ciao! Questa è la mia voce. Il treno parte alle cinque.",
        "Olá! Esta é a minha voz. O trem sai às cinco horas.",
        "こんにちは。これが私の声です。電車は五時に出発します。",
        "안녕하세요. 제 목소리입니다. 기차는 다섯 시에 출발합니다.",
        "مرحباً! هذا صوتي. يغادر القطار في الساعة الخامسة.",
        "Merhaba! Bu benim sesim. Tren saat beşte kalkıyor.",
        "नमस्ते! यह मेरी आवाज़ है। ट्रेन पाँच बजे निकलती है।",
        "你好！这是我的声音。火车五点出发。"};
    const char *shared = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11";
    for (int k=0;k<13;k++) {
        char directory[1024],model[1024],tokens[1024],data[1024],wave[1024];
        const char *id = k<12 ? shared : "vits-piper-zh_CN-huayan-medium";
        snprintf(directory,sizeof(directory),".build/verified-voices/%s",id);
        const SherpaOnnxOfflineTts *tts;
        if(k<12) tts=ot_supertonic_create(directory);
        else {
            snprintf(model,sizeof(model),"%s/zh_CN-huayan-medium.onnx",directory);
            snprintf(tokens,sizeof(tokens),"%s/tokens.txt",directory);
            snprintf(data,sizeof(data),"%s/espeak-ng-data",directory);
            tts=ot_tts_create(model,tokens,data);
        }
        if(!tts) return 1;
        wt_cancel_flag *flag=wt_cancel_create(); struct timespec a,b; clock_gettime(CLOCK_MONOTONIC,&a);
        const SherpaOnnxGeneratedAudio *audio = k<12 ? ot_supertonic_generate(tts,texts[k],codes[k],flag) : ot_tts_generate(tts,texts[k],flag);
        clock_gettime(CLOCK_MONOTONIC,&b);
        if(!audio || audio->n<=0 || audio->sample_rate<=0) return 2;
        double energy=0;
        for(int i=0;i<audio->n;i++) { if(!isfinite(audio->samples[i])) return 3; energy+=audio->samples[i]*audio->samples[i]; }
        if(energy<0.001) return 4;
        if(k<12) snprintf(wave,sizeof(wave),".build/%s-%s-preview.wav",id,codes[k]);
        else snprintf(wave,sizeof(wave),".build/%s-preview.wav",id);
        if(!SherpaOnnxWriteWave(audio->samples,audio->n,audio->sample_rate,wave)) return 5;
        printf("%s samples=%d rate=%d synth=%.3f seconds=%.3f\n",codes[k],audio->n,audio->sample_rate,(b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)/1e9,(double)audio->n/audio->sample_rate);fflush(stdout);
        SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
        wt_cancel_set(flag);
        audio = k<12 ? ot_supertonic_generate(tts,texts[k],codes[k],flag) : ot_tts_generate(tts,texts[k],flag);
        if(audio) return 6;
        SherpaOnnxDestroyOfflineTts(tts);wt_cancel_free(flag);
    }
}
