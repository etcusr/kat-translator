import Foundation
import Darwin
import Combine
import os

@MainActor final class ResourceMonitor: ObservableObject {
    @Published private(set) var appCPU: Double?
    @Published private(set) var systemCPU: Double?
    @Published private(set) var footprint: UInt64?
    @Published private(set) var residentMemory: UInt64?
    @Published private(set) var peakFootprint: UInt64 = 0
    @Published private(set) var availableToApp: UInt64?
    @Published private(set) var storageTotal: UInt64?
    @Published private(set) var storageFree: UInt64?
    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    private var previousProcess: (time: Double, cpu: Double)?
    private var previousSystem: (busy: UInt64, total: UInt64)?
    func reset() { previousProcess = nil; previousSystem = nil; appCPU = nil; systemCPU = nil; peakFootprint = 0 }
    func sample() {
        let time = ProcessInfo.processInfo.systemUptime
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            if let old = previousProcess, time > old.time, cpu >= old.cpu {
                appCPU = min(100, 100 * (cpu-old.cpu) / (time-old.time) / Double(ProcessInfo.processInfo.activeProcessorCount))
            }
            previousProcess = (time, cpu)
        } else { appCPU = nil; previousProcess = nil }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let infoCapacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: infoCapacity) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        footprint = result == KERN_SUCCESS ? info.phys_footprint : nil
        residentMemory = result == KERN_SUCCESS ? info.resident_size : nil
        if let footprint { peakFootprint = max(peakFootprint, footprint) }
        #if os(iOS)
        availableToApp = UInt64(os_proc_available_memory())
        #else
        // macOS has no equivalent per-process iOS allocation budget.
        availableToApp = nil
        #endif
        let disk = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        storageTotal = disk?.volumeTotalCapacity.map { UInt64(max(0, $0)) }
        storageFree = disk?.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
        var cpu = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuCapacity = Int(cpuCount)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: cpuCapacity) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        if cpuResult == KERN_SUCCESS {
            let ticks = cpu.cpu_ticks
            let busy = UInt64(ticks.0) + UInt64(ticks.1) + UInt64(ticks.3)
            let total = busy + UInt64(ticks.2)
            if let old = previousSystem, total > old.total, busy >= old.busy { systemCPU = min(100, 100 * Double(busy-old.busy) / Double(total-old.total)) }
            else { systemCPU = nil }
            previousSystem = (busy, total)
        } else { systemCPU = nil; previousSystem = nil }
    }
}
