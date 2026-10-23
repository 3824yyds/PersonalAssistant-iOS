#include <TargetConditionals.h>
#if TARGET_OS_SIMULATOR
#include "AssistantNative.h"
#include <cstdlib>
extern "C" char *pa_generate(const char *,const char *,int,uint64_t) { return nullptr; }
extern "C" const char *pa_error() { return "模拟器仅用于界面测试，本机模型请在 iPhone 上运行"; }
extern "C" void pa_cancel(uint64_t) {}
extern "C" void pa_release() {}
extern "C" void pa_free(char *p) { std::free(p); }
#else
#include "AssistantNative.h"
#include "llama.h"
#include <atomic>
#include <algorithm>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <mutex>

static std::atomic<uint64_t> cancelled(0);
static llama_model *model = nullptr;
static std::string loaded_path, last_error;
static std::once_flag backend;
static bool abort_generation(void *p) { return cancelled.load() >= *static_cast<uint64_t *>(p); }
extern "C" void pa_cancel(uint64_t id) { uint64_t old = cancelled.load(); while(old < id && !cancelled.compare_exchange_weak(old,id)) {} }
extern "C" void pa_release() { if(model) { llama_model_free(model); model = nullptr; loaded_path.clear(); } }
extern "C" void pa_free(char *value) { if(value) { std::memset(value,0,std::strlen(value)); std::free(value); } }
extern "C" const char *pa_error() { return last_error.c_str(); }
extern "C" char *pa_generate(const char *path,const char *prompt,int max_tokens,uint64_t id) {
    last_error.clear(); llama_context *ctx = nullptr; llama_sampler *sampler = nullptr;
    try {
        if(cancelled.load() >= id) throw std::string("已取消");
        std::call_once(backend,[] { llama_backend_init(); });
        if(!model || loaded_path != path) {
            pa_release(); auto params = llama_model_default_params(); params.n_gpu_layers = 99;
            model = llama_model_load_from_file(path,params);
            if(!model) { params.n_gpu_layers = 0; model = llama_model_load_from_file(path,params); }
            if(!model) throw std::string("本机模型未能加载，请检查可用内存或重新导入模型");
            loaded_path = path;
        }
        auto params = llama_context_default_params(); params.n_ctx = 4096; params.n_batch = 512; params.n_ubatch = 128;
        params.n_threads = 4; params.n_threads_batch = 4; params.abort_callback = abort_generation; params.abort_callback_data = &id;
        ctx = llama_init_from_model(model,params); if(!ctx) throw std::string("无法创建本机推理上下文，请关闭其他应用后重试");
        const llama_vocab *vocab = llama_model_get_vocab(model);
        int count = -llama_tokenize(vocab,prompt,int(std::strlen(prompt)),nullptr,0,true,true);
        if(count <= 0 || count > 3500) throw std::string("当前内容超出本机模型上下文，请缩短问题或使用云端");
        std::vector<llama_token> tokens(count);
        count = llama_tokenize(vocab,prompt,int(std::strlen(prompt)),tokens.data(),count,true,true);
        if(count <= 0) throw std::string("无法解析本机输入");
        for(int offset = 0;offset < count;offset += 512) {
            if(cancelled.load() >= id) throw std::string("已取消");
            auto batch = llama_batch_get_one(tokens.data()+offset,std::min(512,count-offset));
            if(llama_decode(ctx,batch) != 0) throw std::string("本机推理没有完成，请缩短内容后重试");
        }
        sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        llama_sampler_chain_add(sampler,llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler,llama_sampler_init_top_p(0.9f,1));
        llama_sampler_chain_add(sampler,llama_sampler_init_temp(0.65f));
        llama_sampler_chain_add(sampler,llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
        std::string output;
        for(int i=0;i<std::min(max_tokens,4096-count-1);++i) {
            if(cancelled.load() >= id) throw std::string("已取消");
            llama_token token = llama_sampler_sample(sampler,ctx,-1);
            if(llama_vocab_is_eog(vocab,token)) break;
            std::vector<char> piece(256); int size = llama_token_to_piece(vocab,token,piece.data(),int(piece.size()),0,true);
            if(size < 0) { piece.resize(-size); size = llama_token_to_piece(vocab,token,piece.data(),int(piece.size()),0,true); }
            if(size > 0) output.append(piece.data(),size);
            auto batch = llama_batch_get_one(&token,1); if(llama_decode(ctx,batch) != 0) throw std::string("本机生成中断，请重试");
        }
        llama_sampler_free(sampler); sampler=nullptr; llama_free(ctx); ctx=nullptr;
        if(output.empty()) throw std::string("模型没有生成内容，请换一种问法重试");
        return strdup(output.c_str());
    } catch(const std::string &e) { last_error=e; }
      catch(const std::exception &) { last_error="本机智能运行失败，请重新加载模型"; }
      catch(...) { last_error="本机智能发生异常，请重试"; }
    if(sampler) llama_sampler_free(sampler); if(ctx) llama_free(ctx); return nullptr;
}

#endif
