// Short memory read-bandwidth probe. Index decoding streams every weight once per token, so
// sustained read bandwidth predicts tokens/second far better than CPU/GPU model names.
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <thread>
#include <vector>

extern "C" double kat_read_bandwidth_gbps(int threads, size_t bytes_per_thread, double seconds) {
    if (threads < 1 || threads > 16 || bytes_per_thread < (1u << 20)) return -1;
    std::vector<std::vector<uint64_t>> buffers(threads, std::vector<uint64_t>(bytes_per_thread / sizeof(uint64_t)));
    for (auto& buffer : buffers) for (size_t i = 0; i < buffer.size(); ++i) buffer[i] = i * 2654435761u;
    std::atomic<bool> stop{false};
    std::atomic<uint64_t> bytes{0}, sink{0};
    auto worker = [&](const std::vector<uint64_t>& buffer) {
        uint64_t local = 0, read = 0;
        while (!stop.load(std::memory_order_relaxed)) {
            uint64_t a = 0, b = 0, c = 0, d = 0;
            const uint64_t *p = buffer.data();
            for (size_t i = 0; i + 4 <= buffer.size(); i += 4) { a += p[i]; b ^= p[i + 1]; c += p[i + 2]; d ^= p[i + 3]; }
            local += a + b + c + d;
            read += buffer.size() * sizeof(uint64_t);
        }
        bytes += read; sink += local;
    };
    // Warm the pages first so the timed window measures DRAM rather than page faults.
    std::vector<std::thread> pool;
    const auto start = std::chrono::steady_clock::now();
    for (auto& buffer : buffers) pool.emplace_back(worker, std::cref(buffer));
    std::this_thread::sleep_for(std::chrono::duration<double>(seconds));
    stop = true;
    for (auto& t : pool) t.join();
    const double elapsed = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    return sink.load() == 42 ? -2 : bytes.load() / elapsed / 1e9;
}
