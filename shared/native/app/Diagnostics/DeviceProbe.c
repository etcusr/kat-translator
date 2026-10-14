#include "DeviceProbe.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

typedef struct { const uint64_t *data; size_t count; atomic_bool *stop; uint64_t bytes, sink; } Job;

static void *reader(void *raw) {
    Job *job = raw; uint64_t local = 0;
    while (!atomic_load_explicit(job->stop, memory_order_relaxed)) {
        uint64_t a = 0, b = 0, c = 0, d = 0;
        for (size_t i = 0; i + 4 <= job->count; i += 4) { a += job->data[i]; b ^= job->data[i + 1]; c += job->data[i + 2]; d ^= job->data[i + 3]; }
        local += a + b + c + d; job->bytes += job->count * sizeof(uint64_t);
    }
    job->sink = local;
    return NULL;
}

double kat_apple_read_bandwidth_gbps(int threads, size_t bytes_per_thread, double seconds) {
    if (threads < 1 || threads > 16 || bytes_per_thread < (1u << 20)) return -1;
    Job jobs[16]; pthread_t ids[16]; atomic_bool stop = false; int started = 0; double result = -1;
    for (int t = 0; t < threads; ++t) {
        uint64_t *buffer = malloc(bytes_per_thread);
        if (!buffer) break;
        for (size_t i = 0; i < bytes_per_thread / sizeof(uint64_t); ++i) buffer[i] = i * 2654435761u;
        jobs[t] = (Job){ buffer, bytes_per_thread / sizeof(uint64_t), &stop, 0, 0 };
        started++;
    }
    if (started == threads) {
        struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
        for (int t = 0; t < threads; ++t) pthread_create(&ids[t], NULL, reader, &jobs[t]);
        usleep((useconds_t)(seconds * 1e6));
        atomic_store(&stop, true);
        uint64_t bytes = 0, sink = 0;
        for (int t = 0; t < threads; ++t) { pthread_join(ids[t], NULL); bytes += jobs[t].bytes; sink += jobs[t].sink; }
        clock_gettime(CLOCK_MONOTONIC, &b);
        const double elapsed = (b.tv_sec - a.tv_sec) + (b.tv_nsec - a.tv_nsec) / 1e9;
        result = sink == 42 ? -2 : bytes / elapsed / 1e9;
    }
    for (int t = 0; t < started; ++t) free((void *)jobs[t].data);
    return result;
}
