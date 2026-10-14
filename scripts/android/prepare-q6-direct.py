#!/usr/bin/env python3
"""Generate Q6 scale-load specialization without changing shared vendor files.

Direct loads preserve scales exactly but avoid a workgroup-wide barrier per
quant block. Only the Mali F32-activation pipeline opts in through constant 3.
"""
from pathlib import Path
import sys
root,out=map(Path,sys.argv[1:]);src=root/'Dependencies/vendor/llama.cpp/ggml/src/ggml-vulkan/vulkan-shaders'
out.mkdir(parents=True,exist_ok=True)
def write_changed(path,data):
 if not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
for p in src.glob('*.glsl'):write_changed(out/p.name,p.read_bytes())
p=src/'mul_mat_vec_q6_k.comp';s=p.read_text()
def change(a,b,count=1):
 global s
 if s.count(a)!=count:raise RuntimeError('Pinned Q6 shader changed: '+a)
 s=s.replace(a,b)
change('shared FLOAT_TYPE sccache', 'layout (constant_id = 3) const bool DIRECT_SCALES = false;\n\nshared FLOAT_TYPE sccache')
change('            if (i < num_blocks_per_row)\n                sccache[csel][ix][itid] = FLOAT_TYPE(data_a[ib0 + i].scales[itid]);\n            barrier();', '            if (!DIRECT_SCALES) {\n                if (i < num_blocks_per_row)\n                    sccache[csel][ix][itid] = FLOAT_TYPE(data_a[ib0 + i].scales[itid]);\n                barrier();\n            }')
change('        if (all_threads) {', '        if (all_threads && !DIRECT_SCALES) {')
needle='        const FLOAT_TYPE d = FLOAT_TYPE(data_a[ib0 + i].d);'
new=needle+'\n        FLOAT_TYPE scales[4];\n        [[unroll]] for (uint sc = 0; sc < 4; ++sc) {\n            scales[sc] = DIRECT_SCALES ? FLOAT_TYPE(data_a[ib0 + i].scales[s_offset + 2*sc]) : sccache[csel][ix][s_offset + 2*sc];\n        }'
change(needle,new)
for idx,old in enumerate(['sccache[csel][ix][s_offset]','sccache[csel][ix][s_offset + 2]','sccache[csel][ix][s_offset + 4]','sccache[csel][ix][s_offset + 6]']):change(old,f'scales[{idx}]')
write_changed(out/p.name,s.encode())
