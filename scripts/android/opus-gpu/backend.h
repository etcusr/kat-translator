#pragma once
#include "ggml.h"
#include "ggml-backend.h"
#include <vector>
#include <utility>
#include <stdexcept>
#include <cstdio>
#include <chrono>
#include <cstdlib>
#include "ggml-vulkan.h"
#include "ggml-cpu.h"
// Isolated experiment only. No silent CPU fallback: every graph node must be supported.
struct ProbeBackend {
    ggml_backend_t backend=nullptr;
    ggml_backend_buffer_t weights=nullptr;
    bool gpu=false;
    size_t graphs=0,nodes=0;
    double compute=0,transfer=0;
    ProbeBackend() {
        gpu=getenv("KAT_OPUS_GPU") && std::string(getenv("KAT_OPUS_GPU"))=="1";
        backend=gpu ? ggml_backend_vk_init(0) : ggml_backend_cpu_init();
        if(!backend)throw std::runtime_error("Requested backend unavailable");
        if(!gpu)ggml_backend_cpu_set_n_threads(backend,4);
        fprintf(stderr,"PROBE backend=%s gpu=%d\n",ggml_backend_name(backend),gpu);
    }
    ~ProbeBackend(){if(weights)ggml_backend_buffer_free(weights);ggml_backend_free(backend);}
    ggml_backend_buffer_t upload(ggml_context *ctx,bool all=false) {
        std::vector<std::pair<ggml_tensor*,void*>> inputs;
        for(auto *t=ggml_get_first_tensor(ctx);t;t=ggml_get_next_tensor(ctx,t)) {
            if(!t->view_src && (all || t->op==GGML_OP_NONE))inputs.emplace_back(t,t->data);
            t->data=nullptr;t->buffer=nullptr;
        }
        ggml_set_no_alloc(ctx,true);
        auto buffer=ggml_backend_alloc_ctx_tensors(ctx,backend);
        if(!buffer)throw std::runtime_error("Tensor allocation failed");
        if(all)ggml_backend_buffer_set_usage(buffer,GGML_BACKEND_BUFFER_USAGE_WEIGHTS);
        for(auto [t,data]:inputs)ggml_backend_tensor_set(t,data,0,ggml_nbytes(t));
        return buffer;
    }
    ggml_backend_buffer_t run(ggml_context *ctx,ggml_cgraph *graph) {
        auto begin=std::chrono::steady_clock::now();
        auto buf=upload(ctx);
        transfer+=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
        for(int i=0;i<ggml_graph_n_nodes(graph);++i) {
            auto *node=ggml_graph_node(graph,i);
            if(!ggml_backend_supports_op(backend,node))throw std::runtime_error(std::string("Unsupported GPU op: ")+ggml_op_name(node->op));
        }
        begin=std::chrono::steady_clock::now();
        if(ggml_backend_graph_compute(backend,graph)!=GGML_STATUS_SUCCESS)throw std::runtime_error("Graph compute failed");
        compute+=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
        ++graphs;nodes+=ggml_graph_n_nodes(graph);
        return buf;
    }
};
inline ProbeBackend &probe(){static ProbeBackend p;return p;}
