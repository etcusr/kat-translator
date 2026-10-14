// Android adapter for pinned llama.cpp's verified MTP driver. Shared Apple C ABI
// stays unchanged; target and draft contexts share one immutable GGUF model.
#include "index_mtp.h"
#include "common.h"
#include "sampling.h"
#include "speculative.h"
#include "llama.h"
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>

namespace {
using Flag=std::atomic_bool;
bool cancelled(void *p) {return static_cast<Flag *>(p)->load(std::memory_order_relaxed);}
struct Engine {
    common_params params;
    llama_model_ptr model;
    llama_context_ptr target;
    common_speculative_init_result_ptr draft;
};
std::vector<llama_token> tokenize(const llama_vocab *v,const char *text,bool controls) {
    int n=llama_tokenize(v,text,(int)std::strlen(text),nullptr,0,false,controls);
    std::vector<llama_token> result(n<0?-n:n);
    if(!result.empty()) {n=llama_tokenize(v,text,(int)std::strlen(text),result.data(),result.size(),false,controls);if(n<0)throw std::runtime_error("tokenizer");result.resize(n);}
    return result;
}
llama_tokens prompt(Engine &e,const char *prefix,const char *text,const char *suffix) {
    auto *v=llama_model_get_vocab(e.model.get());auto result=tokenize(v,prefix,true);
    for(auto part:{tokenize(v,text,false),tokenize(v,suffix,true)})result.insert(result.end(),part.begin(),part.end());
    return result;
}
// The flag must outlive pending target AND draft work, including error/cancel paths.
struct RunScope {
    llama_context *target,*draft;
    RunScope(llama_context *t,llama_context *d,void *flag):target(t),draft(d) {
        llama_synchronize(t);llama_synchronize(d);
        llama_memory_clear(llama_get_memory(t),true);llama_memory_clear(llama_get_memory(d),true);
        llama_set_abort_callback(t,cancelled,flag);llama_set_abort_callback(d,cancelled,flag);
    }
    ~RunScope() {
        llama_synchronize(target);llama_synchronize(draft);
        llama_set_abort_callback(target,nullptr,nullptr);llama_set_abort_callback(draft,nullptr,nullptr);
    }
};
void validate_logits(llama_context *ctx,int index,int vocab) {
    const float *logits=llama_get_logits_ith(ctx,index);
    if(!logits || std::any_of(logits,logits+vocab,[](float f){return std::isnan(f);}))throw std::runtime_error("invalid target logits");
}
}
void *kat_mtp_load(const char *path,int threads,bool flash) {
    try {
        static std::once_flag once;
        std::call_once(once,[]{llama_backend_init();});
        auto e=std::make_unique<Engine>();auto &p=e->params;
        p.model.path=path;p.n_ctx=2048;p.n_batch=512;p.n_ubatch=128;p.n_parallel=1;
        p.n_gpu_layers=99;p.load_mode=LLAMA_LOAD_MODE_AUTO;p.fit_params=false;p.warmup=false;
        p.cpuparams.n_threads=threads;p.cpuparams_batch.n_threads=threads;
        p.flash_attn_type=flash?LLAMA_FLASH_ATTN_TYPE_ENABLED:LLAMA_FLASH_ATTN_TYPE_DISABLED;
        p.speculative.types={COMMON_SPECULATIVE_TYPE_DRAFT_MTP};p.speculative.draft.n_max=1;p.speculative.draft.n_min=1;
        p.sampling.temp=0.0f;p.sampling.seed=1;
        const auto limits=common_speculative_get_output_limits(p.n_batch,1,1);
        p.n_outputs_max=limits.total;p.n_outputs_max_per_seq=limits.per_seq;
        auto stamp=std::chrono::steady_clock::now();
        auto phase=[&](const char *name) { auto now=std::chrono::steady_clock::now();__android_log_print(ANDROID_LOG_INFO,"KatIndexLoad","%s %.3f s",name,std::chrono::duration<double>(now-stamp).count());stamp=now; };
        auto mp=common_model_params_to_llama(p);e->model.reset(llama_model_load_from_file(path,mp));
        phase("weights");
        if(!e->model || llama_model_n_layer_nextn(e->model.get())!=1)return nullptr;
        auto cp=common_context_params_to_llama(p);e->target.reset(llama_init_from_model(e->model.get(),cp));
        phase("target_context");
        if(!e->target || llama_n_rs_seq(e->target.get())<1)return nullptr;
        auto dp=common_base_params_to_speculative(p);
        e->draft=common_speculative_init_from_params(dp,e->model.get(),e->target.get());
        phase("mtp_context");
        if(!e->draft || !e->draft->context())return nullptr;
        p.speculative.draft.ctx_tgt=e->target.get();p.speculative.draft.ctx_dft=e->draft->context();
        return e.release();
    } catch(const std::exception &ex) {__android_log_print(ANDROID_LOG_ERROR,"KatMTP","load: %s",ex.what());return nullptr;}
}
void kat_mtp_free(void *handle) {delete static_cast<Engine *>(handle);}
int kat_mtp_tokens(void *handle,const char *prefix,const char *text,const char *suffix,int *out,size_t capacity) {
    try {auto values=prompt(*static_cast<Engine *>(handle),prefix,text,suffix);if(out && capacity>=values.size())std::copy(values.begin(),values.end(),out);return values.size();}catch(...){return -1;}
}
int kat_mtp_run(void *handle,const char *prefix,const char *text,const char *suffix,void *flag,char *out,size_t capacity,double *first,int *drafted,int *accepted) {
    if(!handle || !flag || !out || capacity<1 || !first || !drafted || !accepted)return -1;
    out[0]=0;*first=-1;*drafted=*accepted=0;
    try {
        auto &e=*static_cast<Engine *>(handle);auto *target=e.target.get(),*draft=e.draft->context();
        auto tokens=prompt(e,prefix,text,suffix);if(tokens.empty() || tokens.size()>1536)return 1;
        if(cancelled(flag))return 2;
        RunScope scope(target,draft,flag);
        // Fresh speculative driver resets pending hidden rows and sampler state;
        // retaining only KV clear would leak previous-request MTP carryover.
        common_speculative_ptr spec(common_speculative_init(e.params.speculative,1));
        common_sampler_ptr sampler(common_sampler_init(e.model.get(),e.params.sampling));
        if(!spec || !sampler)return -1;
        struct Drain { llama_context *t,*d; ~Drain(){llama_synchronize(t);llama_synchronize(d);} } drain{target,draft};
        const auto *vocab=llama_model_get_vocab(e.model.get());const int nv=llama_vocab_n_tokens(vocab);
        const auto start=std::chrono::steady_clock::now();
        common_batch batch(target);
        // Whole prompt, no n-1 checkpoint split. Process every submitted batch so
        // all target hidden rows reach the MTP driver, including long inputs.
        for(size_t off=0;off<tokens.size();off+=512) {
            if(cancelled(flag))return 2;batch.clear();
            const size_t end=std::min(tokens.size(),off+512);
            for(size_t i=off;i<end;++i)batch.add(tokens[i],i,0,i+1==tokens.size());
            if(llama_process(target,LLAMA_PROCESS_TYPE_DECODE,batch.get()) || !common_speculative_process(spec.get(),batch))return cancelled(flag)?2:-1;
        }
        common_speculative_begin(spec.get(),0,tokens);
        validate_logits(target,-1,nv);
        llama_token last=common_sampler_sample(sampler.get(),target,-1);common_sampler_accept(sampler.get(),last,true);
        std::string result;size_t generated=0;const size_t budget=llama_n_ctx_seq(target)-tokens.size();
        auto emit=[&](llama_token token)->int {
            if(cancelled(flag))return 2;
            if(llama_vocab_is_eog(vocab,token)) {if(result.empty())return -1;std::memcpy(out,result.c_str(),result.size()+1);return 0;}
            if(generated>=budget)return 1;
            if(*first<0)*first=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
            result+=common_token_to_piece(target,token,false);++generated;
            return result.size()+1>capacity?1:3;
        };
        int status=emit(last);if(status!=3)return status;
        while(true) {
            if(cancelled(flag))return 2;
            const int pos=tokens.size();
            if(pos>=int(llama_n_ctx_seq(target)))return 1;
            llama_tokens candidates;
            const int max_draft=std::min(1,int(llama_n_ctx_seq(target))-pos-1);
            if(max_draft>0) {
                common_speculative_get_draft_params(spec.get(),0)={true,max_draft,pos,last,&tokens,&candidates};
                common_speculative_draft(spec.get());
                if(cancelled(flag))return 2;
                if(!llama_memory_seq_rm(llama_get_memory(draft),0,pos,-1))return -3;
            }
            *drafted+=candidates.size();batch.clear();batch.add(last,pos,0,true);
            for(size_t i=0;i<candidates.size();++i)batch.add(candidates[i],pos+1+i,0,true);
            if(llama_process(target,LLAMA_PROCESS_TYPE_DECODE,batch.get()) || !common_speculative_process(spec.get(),batch))return cancelled(flag)?2:-1;
            for(int i=0;i<batch.size();++i)validate_logits(target,i,nv);
            auto ids=common_sampler_sample_and_accept_n(sampler.get(),target,candidates);
            if(ids.empty() || ids.size()>candidates.size()+1)return -3;
            const int naccepted=ids.size()-1;*accepted+=naccepted;
            common_speculative_accept(spec.get(),0,naccepted);
            tokens.push_back(last);
            tokens.insert(tokens.end(),ids.begin(),ids.end()-1);last=ids.back();
            // n_rs_seq=1 is sufficient for our single-candidate rejection. Never
            // silently proceed when target recurrent state cannot be rolled back.
            if(!llama_memory_seq_rm(llama_get_memory(target),0,tokens.size(),-1) ||
               !llama_memory_seq_rm(llama_get_memory(draft),0,tokens.size(),-1))return -3;
            for(auto id:ids){status=emit(id);if(status!=3)return status;}
        }
    } catch(const std::exception &ex) {__android_log_print(ANDROID_LOG_ERROR,"KatMTP","run: %s",ex.what());return cancelled(flag)?2:-1;}
}
