// Darwin 采样：只读系统计数器，开销极小。格式化与计算逻辑在 Sources/MonitorCore。
import Foundation
import Darwin
import IOKit.ps

enum Sampler {
    static func cpuTicks() -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        // cpu_ticks 顺序：USER, SYSTEM, IDLE, NICE
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    static func memoryUsedBytes() -> UInt64 {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        return usedMemoryBytes(internalPages: UInt64(vm.internal_page_count), purgeable: UInt64(vm.purgeable_count),
                               wired: UInt64(vm.wire_count), compressor: UInt64(vm.compressor_page_count),
                               pageSize: UInt64(ps))
    }

    static var memoryTotalBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    static func disk() -> DiskUsage? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity,
              let avail = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskUsage(total: UInt64(max(0, total)), available: UInt64(max(0, avail)))
    }

    /// 内置电池；台式机返回 nil。
    static func battery() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType, let s = parseBattery(desc) { return s }
        }
        return nil
    }
}
