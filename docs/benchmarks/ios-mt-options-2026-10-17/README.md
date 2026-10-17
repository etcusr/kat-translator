# iPhone translation settings comparison — 17 October 2026

Six completed local runs compared Index 9B settings on the same synthetic five-sentence fixture, processing after recording stops. The raw results were inspected when reconciling the project documentation; this report does not represent a new rerun. All six final translations are identical.

| Setting | Full translation | First token | Generation after first token |
|---|---:|---:|---:|
| Current MTP, 2 draft tokens | 7.125 s | 2.066 s | 5.060 s |
| MTP disabled | 6.970 s | 0.518 s | 6.451 s |
| MTP, 3 draft tokens | 6.079 s | 0.664 s | 5.414 s |
| MTP, 1 draft token | 5.618 s | 0.619 s | 4.999 s |
| Q8 KV cache | 5.332 s | 0.727 s | 4.605 s |
| Current MTP, 2 draft tokens, final control | 5.274 s | 0.642 s | 4.632 s |

The final current-setting control matches the Q8 KV variant closely; one draft token falls within the observed baseline generation range. No alternative provides a demonstrated repeatable advantage. MTP remains enabled with two draft tokens. Translation settings and model weights were not changed.

All runs ended at the reported `fair` thermal level. The first baseline has substantially higher first-token latency, so generation time and total translation time must remain separate. A coarse thermal label and a single control repeat do not rule out every thermal/cache effect. These single-fixture measurements cannot establish universal speed or quality equivalence.

Temporary `OT_MTP`, `OT_MTP_DRAFT` and `OT_KV_Q8` experiment switches were removed from the current source. More compressed 9B weights and an iPhone MLX port remain unimplemented proposals; they are not features or validated optimizations. The later [corrected iPhone speech installation](../iphone-speech-correctness-2026-10-17/README.md) supersedes the experiment's installed build. The [initial streaming latency report](../ios-speed-2026-10-17/README.md) is a separate experiment.
