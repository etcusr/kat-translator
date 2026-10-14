#include "SpeechRuntime.h"
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
int main(void) {
    const char *names[] = {"ru_RU-denis-medium", "en_US-ljspeech-high"};
    const char *texts[] = {"Не добавляйте сахар. Поезд отправляется в семнадцать сорок пять.", "Do not cancel the entire order. The train leaves at five forty-five."};
    for (int k=0;k<2;k++) {
        char model[1024],tokens[1024],data[1024],wave[1024];
        snprintf(model,sizeof(model),".build/verified-voices/vits-piper-%s/%s.onnx",names[k],names[k]);
        snprintf(tokens,sizeof(tokens),".build/verified-voices/vits-piper-%s/tokens.txt",names[k]);
        snprintf(data,sizeof(data),".build/verified-voices/vits-piper-%s/espeak-ng-data",names[k]);
        const SherpaOnnxOfflineTts *tts=ot_tts_create(model,tokens,data); if(!tts) return 1;
        wt_cancel_flag *flag=wt_cancel_create(); const SherpaOnnxGeneratedAudio *audio=ot_tts_generate(tts,texts[k],flag);
        if(!audio || audio->n<=0 || audio->sample_rate<=0) return 2;
        double energy=0; for(int i=0;i<audio->n;i++) { if(!isfinite(audio->samples[i])) return 3;energy+=audio->samples[i]*audio->samples[i]; }
        if(energy<0.001) return 4;
        printf("%s rate=%d samples=%d seconds=%.3f energy=%.3f\n",names[k],audio->sample_rate,audio->n,(double)audio->n/audio->sample_rate,energy);
        snprintf(wave,sizeof(wave),".build/%s-smoke.wav",names[k]); SherpaOnnxWriteWave(audio->samples,audio->n,audio->sample_rate,wave);
        const SherpaOnnxVoiceActivityDetector *vad=ot_vad_create("Dependencies/build/speech/silero_vad.onnx");if(!vad) return 5;
        float window[512];int speech_frames=0, quiet_frames=0;
        int frames=(int)((double)audio->n/audio->sample_rate*16000)/512;
        for(int f=0;f<frames+350;f++) {
            for(int j=0;j<512;j++) { int index=(int)((double)(f*512+j)*audio->sample_rate/16000);window[j]=index<audio->n?audio->samples[index]:0; }
            SherpaOnnxVoiceActivityDetectorAcceptWaveform(vad,window,512);
            if(SherpaOnnxVoiceActivityDetectorDetected(vad)) { speech_frames++;quiet_frames=0; } else { quiet_frames++; }
            while(!SherpaOnnxVoiceActivityDetectorEmpty(vad)) SherpaOnnxVoiceActivityDetectorPop(vad);
            if(quiet_frames>=313) break;
        }
        printf("VAD speech_frames=%d final_quiet_frames=%d\n",speech_frames,quiet_frames);
        if(!speech_frames || quiet_frames<313) return 6;
        SherpaOnnxDestroyVoiceActivityDetector(vad);SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);SherpaOnnxDestroyOfflineTts(tts);wt_cancel_free(flag);
    }
    return 0;
}
