#!/usr/bin/env python3
"""Adapt pinned upstream Marian graph code for a strict ggml GPU feasibility probe."""
from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[3]
lab=root/'.build/opus-vulkan-lab'
src=lab/'vendor/sussurro/src'; out=lab/'src';out.mkdir(exist_ok=True)
for name in ['model.cpp','tokenizer.cpp','encoder.cpp','decoder.cpp','sussurro.h']:
 s=(src/name).read_text()
 if name in ['model.cpp','encoder.cpp','decoder.cpp']:s='#include "backend.h"\n'+s
 if name=='model.cpp':
  s=s.replace('load_tokenizer(g, model.vocab);','load_tokenizer(g, model.vocab);\n        probe().weights=probe().upload(model.ctx,true);')
  s=s.replace('if (model.gguf != nullptr) gguf_free(model.gguf);','if (probe().weights) { ggml_backend_buffer_free(probe().weights);probe().weights=nullptr; }\n    if (model.gguf != nullptr) gguf_free(model.gguf);')
 if name in ['encoder.cpp','decoder.cpp']:
  s=s.replace('ggml_graph_compute_with_ctx(ctx, gf, 4);','auto graph_buffer=probe().run(ctx,gf);')
  s=s.replace('std::memcpy(out.data(), cur->data, out.size() * sizeof(float));','ggml_backend_tensor_get(cur,out.data(),0,out.size()*sizeof(float));')
  s=s.replace('''        const float * kp = (const float *) knew_t[il]->data;
        const float * vp = (const float *) vnew_t[il]->data;
        cache.k[il].insert(cache.k[il].end(), kp, kp + d);
        cache.v[il].insert(cache.v[il].end(), vp, vp + d);''','''        auto offset=cache.k[il].size();cache.k[il].resize(offset+d);cache.v[il].resize(offset+d);
        ggml_backend_tensor_get(knew_t[il],cache.k[il].data()+offset,0,d*sizeof(float));
        ggml_backend_tensor_get(vnew_t[il],cache.v[il].data()+offset,0,d*sizeof(float));''')
  s=s.replace('std::memcpy(out.data(), logits->data, (size_t) vocab * sizeof(float));','ggml_backend_tensor_get(logits,out.data(),0,(size_t)vocab*sizeof(float));')
  s=s.replace('ggml_free(ctx);','ggml_backend_buffer_free(graph_buffer);\n    ggml_free(ctx);')
 (out/name).write_text(s)
shutil.copy2(root/'scripts/android/opus-gpu/backend.h',out/'backend.h')
