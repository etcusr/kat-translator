#include "SpeechRuntime.h"
#include <stdio.h>
#include <math.h>
int main() {
const char *codes[]={"nl","pl","ro","sv","vi","id","uk","cs","el","da","hu","fi","sk","bg","lt","sl","et","lv","hr"};
const char *texts[]={"Hallo! Dit is een voorbeeld van mijn stem.","Dzień dobry! Tak brzmi mój głos.","Bună ziua! Aceasta este vocea mea.","Hej! Så här låter min röst.","Xin chào! Đây là giọng nói của tôi.","Halo! Ini contoh suara saya.","Вітаю! Так звучить мій голос.","Dobrý den! Tak zní můj hlas.","Γεια σας! Αυτή είναι η φωνή μου.","Hej! Sådan lyder min stemme.","Jó napot! Így szól a hangom.","Hei! Tältä ääneni kuulostaa.","Dobrý deň! Takto znie môj hlas.","Здравейте! Така звучи моят глас.","Sveiki! Taip skamba mano balsas.","Pozdravljeni! Tako zveni moj glas.","Tere! Nii kõlab minu hääl.","Labdien! Tā skan mana balss.","Dobar dan! Ovako zvuči moj glas."};
const char *id="sherpa-onnx-supertonic-3-tts-int8-2026-05-11";
const SherpaOnnxOfflineTts *tts=ot_supertonic_create(".build/verified-voices/sherpa-onnx-supertonic-3-tts-int8-2026-05-11");
if (!tts) return 1;
wt_cancel_flag *flag=wt_cancel_create();
for(int k=0;k<20;k++) {
 if(k==19) { SherpaOnnxDestroyOfflineTts(tts); tts=ot_tts_create("model-store/downloads/mms-ban-model.onnx","model-store/downloads/mms-ban-tokens.txt",""); if(!tts) return 2; }
 const SherpaOnnxGeneratedAudio *a=k<19 ? ot_supertonic_generate(tts,texts[k],codes[k],flag) : ot_tts_generate(tts,"Om swastiastu. Punapi gatra?",flag);
 if(!a || a->n<=0) return 3;
 double energy=0;for(int i=0;i<a->n;i++){if(!isfinite(a->samples[i]))return 4;energy+=a->samples[i]*a->samples[i];}
 if(energy<0.001)return 5;
 char out[1024];if(k<19)snprintf(out,sizeof(out),".build/speech-expansion/%s-%s-preview.wav",id,codes[k]);else snprintf(out,sizeof(out),".build/speech-expansion/mms-tts-ban-onnx-preview.wav");
 if(!SherpaOnnxWriteWave(a->samples,a->n,a->sample_rate,out))return 6;
 printf("%s samples=%d rate=%d duration=%.2f energy=%f\n",k<19?codes[k]:"ban",a->n,a->sample_rate,(double)a->n/a->sample_rate,energy);fflush(stdout);
 SherpaOnnxDestroyOfflineTtsGeneratedAudio(a);
}
SherpaOnnxDestroyOfflineTts(tts);wt_cancel_free(flag);return 0;
}
