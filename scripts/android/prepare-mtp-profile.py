#!/usr/bin/env python3
"""Generate diagnostic source copies without changing shared llama.cpp."""
import sys
from pathlib import Path

root, output = map(Path, sys.argv[1:])
vendor=root/'Dependencies/vendor/llama.cpp'
header=root/'scripts/android/native/mtp_profile.h'
text=(vendor/'common/speculative.cpp').read_text()
begin=text.index('struct common_speculative_impl_draft_mtp ')
end=text.index('// state of self-speculation',begin)
section=text[begin:end]
patches=[
('void begin(llama_seq_id seq_id, const llama_tokens & prompt) override {','begin','(int)prompt.size()'),
('bool process(const common_batch & batch_in) override {','process','(int)batch_in.size()'),
('void draft(common_speculative_draft_params_vec & dparams) override {','draft','0'),
('void accept(llama_seq_id seq_id, uint16_t n_accepted, bool /*is_other*/) override {','accept','n_accepted'),
]
for needle,name,tokens in patches:
    assert section.count(needle)==1,needle
    section=section.replace(needle,needle+f'\n        KatMtpStage kat_stage("{name}", params.ctx_tgt, params.ctx_dft, {tokens});')
text=text[:begin]+section+text[end:]
text=text.replace('#include "../src/llama-ext.h"',f'#include "{vendor}/src/llama-ext.h"')
(output/'speculative-profile.cpp').write_text(f'#include "{header}"\n'+text)
text=(vendor/'tools/server/server-context.cpp').read_text()
needle='            ret = llama_process(ctx_tgt, LLAMA_PROCESS_TYPE_DECODE, batch.view.get());'
assert text.count(needle)==1
text=text.replace(needle,'            KatMtpStage kat_stage("target", ctx_tgt, nullptr, batch.view.size());\n'+needle)
(output/'server-context-profile.cpp').write_text(f'#include "{header}"\n'+text)
