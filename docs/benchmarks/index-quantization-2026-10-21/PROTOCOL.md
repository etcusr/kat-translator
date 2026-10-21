# Index 9B GGUF quantization comparison — 21 October 2026

Frozen before model outputs: compare current Q4_K_M to IQ4_XS, Q4_K_S and Q3_K_M from the same official revision d01404384ba429b93f5f63d43573812d103b5bcd. Verify full SHA-256 before inference. Use the same frozen native llama.cpp/Metal runtime for all four; this is not the main Mac MLX/MTP2 backend and is not an iPhone performance prediction.

30 fixed RU↔EN cases: 16 earlier travel/ambiguity/context cases, six earlier MTP cases including public excerpts and a repetitive stress input, four technical excerpts from the synthetic glossary corpus, four new semantic challenge cases. Corpus selection precedes all outputs. No previous Q3_K_M run was found; do not label earlier translations as Q3. Source provenance stays with each case.

Two dedicated warmups, then two independent measured passes per model, deterministic shuffled case order. Fresh model process, greedy sampling, 2048-token context, maximum 1536 prompt tokens, four CPU threads, 99 GPU layers, flash attention, no MTP, no glossary. Context resets each request. Measure load separately, total request latency and native first-token latency; report matched-case medians and corpus sums. Repeat baseline at the end on all 30 cases (one measured pass) as a drift control.

Sample process physical footprint, resident memory and Metal allocated buffer bytes every 100 ms. With GGML_METAL_NO_RESIDENCY=1 (the same residency policy used in Kat iOS), mmap-backed model buffers may not appear in physical footprint; report these metrics separately and never sum them. Metal allocated bytes are buffer allocations, not measured physical RAM residency. Peak is sampled, not an exact allocator maximum. Log process resident high-water mark separately (not reset per case), system swap and thermal state. Pause on serious/critical thermal state. Sequential runs and no overlapping downloads/compilation during timings. Mac remains in its ordinary desktop state, so record interference and avoid hardware-level claims.

Quality: compare all distinct outputs to source meaning, with explicit attention to omissions, added facts, negation, conditions, numbers/dates, entities and role assignments. Different wording alone is not an error. Prepare anonymized output labels before comparative review; a single-model reviewer is not independent native-speaker validation. No BLEU-like score is treated as translation quality. Report both regressions and improvements relative to Q4_K_M, repeat stability, examples and limitations. No production/app/model replacement.

Research artifacts and model downloads stay separate. Limited disk space requires retaining only one newly downloaded quantization at a time; remove only this task's verified download after its complete results are saved. Preserve existing Q4_K_M and all application models.

## Recorded execution notes

- Initial Q4_K_M smoke (two challenge cases) is excluded from final timing. It exposed mmap accounting differences, so Metal allocation sampling was added before every measured run.
- Q3 download was interrupted after pausing its HTTP/2 stream during the baseline run; it resumed with a range request, then passed the complete official SHA-256. No partial file was used.
- First two models stayed at 631.94 MiB system swap. During IQ4_XS, system swap increased from 591.88 to 928.12 MiB while thermal state remained nominal. This is an ordinary working Mac, not a controlled clean-boot memory benchmark; small latency differences must not be called a speed improvement.
- Quality review is performed in two anonymized pairs as completed artifacts become available; per-case labels come from the same fixed four-model shuffle. The key is opened only after all 120 annotations.

For presentation, also separate the 29 ordinary cases from the artificial repeated-block stress case: omission changes generated length and can make that stress request appear faster. Preserve full 30-case sums and all raw measurements, rather than silently excluding it. This reporting split is made before revealing model identities in the quality review.
