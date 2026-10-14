#include "SpeechRuntime.h"
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
 if(argc!=4)return 1;
 const SherpaOnnxOfflineRecognizer *r=ot_omni_create(argv[1],argv[2]); if(!r)return 2;
 const SherpaOnnxWave *w=SherpaOnnxReadWave(argv[3]); if(!w)return 3;
 const SherpaOnnxOfflineStream *s=SherpaOnnxCreateOfflineStream(r);if(!s)return 4;
 SherpaOnnxAcceptWaveformOffline(s,w->sample_rate,w->samples,w->num_samples);
 SherpaOnnxDecodeOfflineStream(r,s);
 const SherpaOnnxOfflineRecognizerResult *result=SherpaOnnxGetOfflineStreamResult(s);
 int ok=result && result->text && strlen(result->text)>0;
 if(ok)printf("%s\n",result->text);
 if(result)SherpaOnnxDestroyOfflineRecognizerResult(result);
 SherpaOnnxDestroyOfflineStream(s);SherpaOnnxFreeWave(w);SherpaOnnxDestroyOfflineRecognizer(r);
 return ok?0:5;
}
