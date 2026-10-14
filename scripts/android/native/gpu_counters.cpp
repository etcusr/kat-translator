// Standalone diagnostic sampler; never linked into the application.
#include <hwcpipe/gpu.hpp>
#include <hwcpipe/sampler.hpp>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <unistd.h>
struct Counter { hwcpipe_counter id; const char *name; };
int main(int argc,char **argv) {
    char *end=nullptr;
    const long count=argc==2?std::strtol(argv[1],&end,10):0;
    if(argc!=2 || !end || *end || count<1 || count>3000) {std::fprintf(stderr,"Usage: kat_gpu_counters SAMPLES(1..3000), interval200ms\n");return 2;}
    hwcpipe::gpu gpu(0);
    if(!gpu) {std::fprintf(stderr,"GPU counter device unavailable\n");return 2;}
    std::fprintf(stderr,"cores=%llu busWidth=%llu; counters are device-wide, not per kernel\n",(unsigned long long)gpu.num_shader_cores(),(unsigned long long)gpu.bus_width());
    hwcpipe::sampler_config config(gpu);
    std::vector<Counter> counters;
    for(auto c:std::vector<Counter>{{MaliGPUActiveCy,"gpuActiveCycles"},{MaliCompQueueActiveCy,"computeCycles"},
        {MaliAnyActiveCy,"shaderCycles"},{MaliExtBusRdBy,"readBytes"},{MaliExtBusWrBy,"writeBytes"},
        {MaliExtBusRdStallRate,"readStallPercent"},{MaliEngStarveCy,"issueStarveCycles"},
        {MaliEngFMAPipeUtil,"fmaPercent"},{MaliLSUtil,"loadStorePercent"},{MaliCoreUtil,"corePercent"}}) {
        auto ec=config.add_counter(c.id);
        if(ec)std::fprintf(stderr,"Unsupported %s: %s\n",c.name,ec.message().c_str());
        else counters.push_back(c);
    }
    if(counters.empty())return 2;
    hwcpipe::sampler<> sampler(config);
    auto ec=sampler.start_sampling();
    if(ec) {std::fprintf(stderr,"%s\n",ec.message().c_str());return 2;}
    std::printf("elapsedSeconds,intervalSeconds");for(auto c:counters)std::printf(",%s",c.name);std::puts("");
    auto start=std::chrono::steady_clock::now(),previous=start;
    bool failed=false;
    for(long i=0;i<count;++i) {
        usleep(200000);
        ec=sampler.sample_now();
        if(ec){std::fprintf(stderr,"sample failed: %s\n",ec.message().c_str());failed=true;break;}
        auto now=std::chrono::steady_clock::now();
        std::printf("%.6f,%.6f",std::chrono::duration<double>(now-start).count(),std::chrono::duration<double>(now-previous).count());previous=now;
        for(auto c:counters) {
            hwcpipe::counter_sample s;ec=sampler.get_counter_value(c.id,s);
            if(ec){std::fprintf(stderr,"read failed: %s\n",ec.message().c_str());failed=true;std::printf(",nan");continue;}
            double value=s.type==hwcpipe::counter_sample::type::uint64?double(s.value.uint64):s.value.float64;
            if(!std::isfinite(value))failed=true;
            std::printf(",%.9g",value);
        }
        std::puts("");std::fflush(stdout);
        if(failed)break;
    }
    ec=sampler.stop_sampling();if(ec)failed=true;
    return failed?2:0;
}
