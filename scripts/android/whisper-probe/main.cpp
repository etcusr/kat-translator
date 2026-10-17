#include "whisper.h"
#include "sherpa-onnx/c-api/c-api.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <memory>
using Clock=std::chrono::steady_clock;
static double secs(Clock::time_point t){return std::chrono::duration<double>(Clock::now()-t).count();}
int main(int argc,char**argv){
 if(argc<4){fprintf(stderr,"Usage: whisper-probe MODEL WAV THREADS [LANGUAGE]\n");return 2;}
 setenv("ORT_DISABLE_TELEMETRY","1",1);
 fprintf(stderr,"%s\n",whisper_print_system_info());
 auto*w=SherpaOnnxReadWave(argv[2]);if(!w||w->sample_rate!=16000)return 3;
 auto cp=whisper_context_default_params();cp.use_gpu=false;
 auto start=Clock::now();auto*ctx=whisper_init_from_file_with_params(argv[1],cp);if(!ctx)return 4;
 printf("load_seconds=%.6f\n",secs(start));fflush(stdout);
 auto p=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
 p.translate=false;p.no_context=true;p.detect_language=false;p.language=argc>4?argv[4]:"auto";p.temperature=0;p.temperature_inc=0;p.n_threads=atoi(argv[3]);
 p.print_realtime=false;p.print_progress=false;p.print_timestamps=false;p.print_special=false;
 start=Clock::now();int rc=whisper_full(ctx,p,w->samples,w->num_samples);printf("generation_seconds=%.6f rc=%d\n",secs(start),rc);
 for(int i=0;i<whisper_full_n_segments(ctx);i++)printf("%s",whisper_full_get_segment_text(ctx,i));puts("");fflush(stdout);
 whisper_print_timings(ctx);whisper_free(ctx);SherpaOnnxFreeWave(w);return rc;
}
