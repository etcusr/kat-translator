#include "SpeechRuntime.h"
#include <stdio.h>
#include <math.h>
#include <time.h>
int main(void) {
    const char *names[]={"ru_RU-denis-medium","ru_RU-irina-medium","en_US-ljspeech-high","en_US-lessac-medium"};
    for(int k=0;k<4;k++) {
        char model[1024],tokens[1024],data[1024],wave[1024];
        snprintf(model,sizeof(model),".build/verified-voices/vits-piper-%s/%s.onnx",names[k],names[k]);
        snprintf(tokens,sizeof(tokens),".build/verified-voices/vits-piper-%s/tokens.txt",names[k]);
        snprintf(data,sizeof(data),".build/verified-voices/vits-piper-%s/espeak-ng-data",names[k]);
        const char *text=k<2?"Здравствуйте! Так звучит мой голос. Поезд отправляется в семнадцать сорок пять.":"Hello! This is a sample of my voice. The train leaves at five forty-five.";
        const SherpaOnnxOfflineTts *tts=ot_tts_create(model,tokens,data);if(!tts)return 1;
        wt_cancel_flag *flag=wt_cancel_create();struct timespec a,b;clock_gettime(CLOCK_MONOTONIC,&a);
        const SherpaOnnxGeneratedAudio *audio=ot_tts_generate(tts,text,flag);clock_gettime(CLOCK_MONOTONIC,&b);
        if(!audio || audio->n<=0 || audio->sample_rate<=0)return 2;
        double energy=0;for(int i=0;i<audio->n;i++){if(!isfinite(audio->samples[i]))return 3;energy+=audio->samples[i]*audio->samples[i];}
        if(energy<0.001)return 4;
        snprintf(wave,sizeof(wave),".build/vits-piper-%s-preview.wav",names[k]);
        if(!SherpaOnnxWriteWave(audio->samples,audio->n,audio->sample_rate,wave))return 5;
        printf("%s samples=%d rate=%d synth=%.3f seconds=%.3f\n",names[k],audio->n,audio->sample_rate,(b.tv_sec-a.tv_sec)+(b.tv_nsec-a.tv_nsec)/1e9,(double)audio->n/audio->sample_rate);fflush(stdout);
        SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);SherpaOnnxDestroyOfflineTts(tts);wt_cancel_free(flag);
    }
}
