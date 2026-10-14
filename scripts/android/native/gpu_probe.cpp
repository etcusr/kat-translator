// Isolated matmul accuracy/performance probe; never used for application inference.
#include "ggml.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"
#include "ggml-cpu.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <vector>

struct Graph {
    ggml_context *ctx;
    ggml_tensor *a, *b, *out;
    ggml_cgraph *graph;
    ggml_backend_buffer_t buffer;
    Graph(ggml_backend_t backend, ggml_type type, int m, int n, int k) {
        ctx=ggml_init({2*1024*1024,nullptr,true});
        if(!ctx) throw std::runtime_error("context allocation");
        a=ggml_new_tensor_2d(ctx,type,k,m); b=ggml_new_tensor_2d(ctx,GGML_TYPE_F32,k,n);
        ggml_set_input(a); ggml_set_input(b);
        out=ggml_mul_mat(ctx,a,b);ggml_set_output(out);
        graph=ggml_new_graph(ctx);ggml_build_forward_expand(graph,out);
        if(!ggml_backend_supports_op(backend,out)) throw std::runtime_error("unsupported matmul");
        buffer=ggml_backend_alloc_ctx_tensors(ctx,backend);
        if(!buffer) throw std::runtime_error("buffer allocation");
    }
    ~Graph() { ggml_backend_buffer_free(buffer);ggml_free(ctx); }
};

static void compute(ggml_backend_t backend, Graph &g) {
    if(ggml_backend_graph_compute(backend,g.graph)!=GGML_STATUS_SUCCESS) throw std::runtime_error("compute");
    ggml_backend_synchronize(backend);
}
static float value(uint32_t &state) {
    state^=state<<13; state^=state>>17; state^=state<<5;
    return float(int32_t(state))/2147483648.0f;
}
static bool probe(ggml_backend_t gpu,ggml_backend_t cpu,ggml_type type,int m,int n,int k) {
    Graph a(gpu,type,m,n,k),r(cpu,type,m,n,k);
    std::vector<float> weights(size_t(m)*k),input(size_t(n)*k),actual(size_t(m)*n),expected(actual.size());
    uint32_t seed=123456789;
    for(auto &v:weights)v=value(seed);
    std::vector<uint8_t> quant(ggml_nbytes(a.a));
    if(ggml_quantize_chunk(type,weights.data(),quant.data(),0,m,k,nullptr)!=quant.size()) throw std::runtime_error("quantization size");
    weights.clear();weights.shrink_to_fit();
    ggml_backend_tensor_set(a.a,quant.data(),0,quant.size());ggml_backend_tensor_set(r.a,quant.data(),0,quant.size());
    double worst=0,max_error=0;
    bool finite=true;
    for(int input_pass=0;input_pass<2;++input_pass) {
        for(auto &v:input)v=value(seed);
        ggml_backend_tensor_set(a.b,input.data(),0,input.size()*4);ggml_backend_tensor_set(r.b,input.data(),0,input.size()*4);
        compute(cpu,r);compute(gpu,a);
        ggml_backend_tensor_get(a.out,actual.data(),0,actual.size()*4);ggml_backend_tensor_get(r.out,expected.data(),0,expected.size()*4);
        double error=0,power=0;
        for(size_t i=0;i<actual.size();++i) {
            finite &= std::isfinite(actual[i]) && std::isfinite(expected[i]);
            double delta=double(actual[i])-expected[i];error+=delta*delta;power+=double(expected[i])*expected[i];max_error=std::max(max_error,std::abs(delta));
        }
        worst=std::max(worst,error/std::max(power,1e-30));
    }
    std::vector<double> times;
    // Let the mobile GPU leave its idle DVFS state before short matrix timings.
    auto warm_start=std::chrono::steady_clock::now();
    do {compute(gpu,a);} while(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-warm_start).count()<50.);
    auto measure_start=std::chrono::steady_clock::now();
    for(int i=0;i<1000;++i) {
        auto start=std::chrono::steady_clock::now();compute(gpu,a);
        times.push_back(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count());
        if(i>=6 && std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-measure_start).count()>=200.)break;
    }
    std::sort(times.begin(),times.end());
    const bool passed=finite && worst<5e-4; // Same limit as upstream test_mul_mat.
    std::printf("{\"type\":\"%s\",\"m\":%d,\"n\":%d,\"k\":%d,\"medianMs\":%.6f,\"minMs\":%.6f,\"maxMs\":%.6f,\"iterations\":%zu,\"nmse\":%.9g,\"maxAbsError\":%.9g,\"finite\":%s,\"passed\":%s}\n",ggml_type_name(type),m,n,k,times[times.size()/2],times.front(),times.back(),times.size(),worst,max_error,finite?"true":"false",passed?"true":"false");
    std::fflush(stdout);return passed;
}
int main(int argc,char **argv) {
    try {
        int m=1024,n=1,k=4096;
        ggml_type type=GGML_TYPE_Q4_K;
        if(argc!=1 && argc!=5) throw std::runtime_error("usage: kat_gpu_probe [4|6 M N K]");
        if(argc==5) {
            if(std::strcmp(argv[1],"4")!=0 && std::strcmp(argv[1],"6")!=0) throw std::runtime_error("quant type must be 4 or 6");
            type=std::strcmp(argv[1],"6")==0?GGML_TYPE_Q6_K:GGML_TYPE_Q4_K;
            auto dimension=[](const char *s,long maximum) {
                char *end=nullptr;long value=std::strtol(s,&end,10);
                if(end==s || *end || value<1 || value>maximum) throw std::runtime_error("invalid matrix dimension");
                return int(value);
            };
            m=dimension(argv[2],248320);n=dimension(argv[3],512);k=dimension(argv[4],12288);
            if(k%256) throw std::runtime_error("K must be a multiple of the 256-element quant block");
        }
        ggml_backend_load_all();
        auto dev=ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
        if(!dev)dev=ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);
        if(!dev)throw std::runtime_error("GPU missing; no fallback");
        auto gpu=ggml_backend_dev_init(dev,nullptr);auto cpu=ggml_backend_cpu_init();
        if(!gpu || !cpu)throw std::runtime_error("backend init");
        ggml_backend_cpu_set_n_threads(cpu,4);
        std::fprintf(stderr,"GPU: %s\n",ggml_backend_dev_name(dev));
        bool passed=true;
        if(argc==5) passed=probe(gpu,cpu,type,m,n,k);
        else for(auto type:{GGML_TYPE_Q4_K,GGML_TYPE_Q6_K}) for(int n:{1,2,3,4,16,32,33,46,64,65,82,128}) passed=probe(gpu,cpu,type,1024,n,4096)&&passed;
        ggml_backend_free(gpu);ggml_backend_free(cpu);
        return passed?0:1;
    } catch(const std::exception &e) {std::fprintf(stderr,"Probe failed: %s\n",e.what());return 2;}
}
