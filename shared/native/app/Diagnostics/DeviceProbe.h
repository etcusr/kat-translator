#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/// Sustained multi-thread memory read bandwidth in GB/s (negative on failure). Same method as
/// Android memory_probe.cpp: Index decoding streams every weight once per generated token.
double kat_apple_read_bandwidth_gbps(int threads, size_t bytes_per_thread, double seconds);
#ifdef __cplusplus
}
#endif
