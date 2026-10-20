#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <mach/mach.h>
#include "whisper.h"
#include <vector>

static NSDictionary *memorySnapshot() {
    task_vm_info_data_t v{};
    mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
    task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&v, &n);
    return @{@"footprint": @(v.phys_footprint),
             @"residentPeak": @(v.resident_size_peak),
             @"metalAllocated": @(MTLCreateSystemDefaultDevice().currentAllocatedSize)};
}

// The manifest contains only explicit fixture paths. Never reads Kat's container.
int runWhisperBench(NSString *model, NSString *manifest, NSString *output, int repeats) {
    @autoreleasepool {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfFile:manifest options:0 error:&error];
        NSArray *cases = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        if (![cases isKindOfClass:NSArray.class] || cases.count == 0) return 2;
        NSMutableArray *rows = [NSMutableArray new];
        NSMutableDictionary *report = [@{
            @"model": model.lastPathComponent, @"rows": rows,
            @"device": MTLCreateSystemDefaultDevice().name ?: @"unknown",
            @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
            @"physicalMemory": @(NSProcessInfo.processInfo.physicalMemory),
            @"systemInfo": [NSString stringWithUTF8String:whisper_print_system_info()],
            @"threads": @4, @"flashAttention": @YES,
            @"temperature": @0, @"temperatureIncrement": @0, @"noContext": @YES,
            @"coremlUnitsRequested": NSProcessInfo.processInfo.environment[@"BENCH_COREML_UNITS"] ?: @"all",
            @"started": @(NSDate.date.timeIntervalSince1970)
        } mutableCopy];
        void (^save)(void) = ^{
            NSData *json = [NSJSONSerialization dataWithJSONObject:report
                options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
            [json writeToFile:output atomically:YES];
        };
        auto cp = whisper_context_default_params();
        cp.use_gpu = true;
        cp.flash_attn = true;
        double started = NSProcessInfo.processInfo.systemUptime;
        whisper_context *ctx = whisper_init_from_file_with_params(model.fileSystemRepresentation, cp);
        report[@"loadSeconds"] = @(NSProcessInfo.processInfo.systemUptime - started);
        report[@"memoryLoaded"] = memorySnapshot();
        if (!ctx) { report[@"error"] = @"load failed"; save(); return 3; }
        save();
        for (int pass = 0; pass <= repeats; ++pass) {
            NSArray *ordered = pass % 2 ? cases.reverseObjectEnumerator.allObjects : cases;
            for (NSDictionary *item in ordered) {
                @autoreleasepool {
                    NSString *path = item[@"path"];
                    if (![path hasPrefix:@"/"])
                        path = [manifest.stringByDeletingLastPathComponent stringByAppendingPathComponent:path];
                    NSData *pcm = [NSData dataWithContentsOfFile:path];
                    if (!pcm || pcm.length % sizeof(float) || pcm.length == 0) {
                        report[@"error"] = @"invalid PCM fixture"; save(); whisper_free(ctx); return 4;
                    }
                    std::vector<float> samples(pcm.length / sizeof(float));
                    memcpy(samples.data(), pcm.bytes, pcm.length);
                    auto p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
                    p.translate = false; p.no_context = true; p.detect_language = false;
                    p.language = [item[@"language"] UTF8String];
                    p.temperature = 0; p.temperature_inc = 0; p.n_threads = 4;
                    p.print_realtime = false; p.print_progress = false;
                    p.print_timestamps = false; p.print_special = false;
                    int thermal = (int)NSProcessInfo.processInfo.thermalState;
                    whisper_reset_timings(ctx);
                    double start = NSProcessInfo.processInfo.systemUptime;
                    int rc = whisper_full(ctx, p, samples.data(), (int)samples.size());
                    double seconds = NSProcessInfo.processInfo.systemUptime - start;
                    NSMutableString *text = [NSMutableString new];
                    for (int i = 0; rc == 0 && i < whisper_full_n_segments(ctx); ++i)
                        [text appendString:[NSString stringWithUTF8String:whisper_full_get_segment_text(ctx, i)]];
                    [rows addObject:@{
                        @"id": item[@"id"], @"pass": @(pass), @"warmup": @(pass == 0),
                        @"seconds": @(seconds), @"audioSeconds": @(samples.size() / 16000.0),
                        @"text": text, @"code": @(rc), @"memory": memorySnapshot(),
                        @"thermalBefore": @(thermal),
                        @"thermalAfter": @((int)NSProcessInfo.processInfo.thermalState)
                    }];
                    save();
                    fprintf(stderr, "BENCH %s pass=%d seconds=%.6f rc=%d thermal=%d\n",
                        [item[@"id"] UTF8String], pass, seconds, rc,
                        (int)NSProcessInfo.processInfo.thermalState);
                    whisper_print_timings(ctx);
                    if (rc) { whisper_free(ctx); return 5; }
                }
            }
        }
        whisper_free(ctx);
        report[@"completed"] = @YES;
        report[@"memoryAfterUnload"] = memorySnapshot();
        save();
        return 0;
    }
}

#ifndef BENCH_IOS
int main(int argc, char **argv) {
    if (argc != 5) return 1;
    return runWhisperBench(@(argv[1]), @(argv[2]), @(argv[3]), atoi(argv[4]));
}
#endif
