// Decode-like GPU probe: Q4_K matrix x vector on the same ggml backend Index uses. Weights are
// zero (no download); the kernels still stream every weight byte, which is what bounds decode.
#include "ggml.h"
#include "ggml-alloc.h"
#include "ggml-backend.h"
#include <chrono>

extern "C" double kat_gpu_matvec_gbps(ggml_backend_dev_t device, double seconds) {
    if (!device) return -1;
    ggml_backend_t backend = ggml_backend_dev_init(device, nullptr);
    if (!backend) return -1;
    constexpr int matrices = 4, rows = 8192, cols = 8192;
    ggml_init_params params{ggml_tensor_overhead() * 16 + ggml_graph_overhead(), nullptr, true};
    ggml_context *ctx = ggml_init(params);
    double result = -1;
    if (ctx) {
        ggml_tensor *x = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, cols, 1);
        ggml_cgraph *graph = ggml_new_graph(ctx);
        size_t weight_bytes = 0;
        for (int i = 0; i < matrices; ++i) {
            ggml_tensor *w = ggml_new_tensor_2d(ctx, GGML_TYPE_Q4_K, cols, rows);
            weight_bytes += ggml_nbytes(w);
            ggml_build_forward_expand(graph, ggml_mul_mat(ctx, w, x));
        }
        ggml_backend_buffer_t buffer = ggml_backend_alloc_ctx_tensors(ctx, backend);
        if (buffer) {
            ggml_backend_buffer_clear(buffer, 0);
            // Warm-up compiles pipelines and faults in pages outside the timed window.
            if (ggml_backend_graph_compute(backend, graph) == GGML_STATUS_SUCCESS) {
                int runs = 0;
                const auto start = std::chrono::steady_clock::now();
                double elapsed = 0;
                while (elapsed < seconds) {
                    if (ggml_backend_graph_compute(backend, graph) != GGML_STATUS_SUCCESS) { runs = -1; break; }
                    ++runs;
                    elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
                }
                if (runs > 0) result = runs * static_cast<double>(weight_bytes) / elapsed / 1e9;
            }
            ggml_backend_buffer_free(buffer);
        }
        ggml_free(ctx);
    }
    ggml_backend_free(backend);
    return result;
}
