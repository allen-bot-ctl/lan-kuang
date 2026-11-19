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

    /// v0.1.12：已缓存文件（external pages），与活动监视器「已缓存文件」同口径。
    static func memoryCachedBytes() -> UInt64 {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        return UInt64(vm.external_page_count) * UInt64(ps)
    }

    /// v0.1.12：已使用的交换（sysctl vm.swapusage）。
    static func swapUsedBytes() -> UInt64 {
        var x = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &x, &len, nil, 0) == 0 else { return 0 }
        return x.xsu_used
    }

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

    /// 所有处于 up 状态的网卡累计收发字节（sysctl NET_RT_IFLIST2，64 位 if_data64）。过滤交给 MonitorCore.isPhysicalInterface。
    static func interfaceCounters() -> [String: InterfaceCounters] {
        var out: [String: InterfaceCounters] = [:]
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return out }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return out }
        buf.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = base.advanced(by: off).assumingMemoryBound(to: if_msghdr.self).pointee
                let msgLen = Int(hdr.ifm_msglen)
                if msgLen == 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, (hdr.ifm_flags & IFF_UP) != 0 {
                    let h2 = base.advanced(by: off).assumingMemoryBound(to: if_msghdr2.self).pointee
                    let sdlPtr = base.advanced(by: off + MemoryLayout<if_msghdr2>.size).assumingMemoryBound(to: sockaddr_dl.self)
                    let nlen = Int(sdlPtr.pointee.sdl_nlen)
                    let namePtr = UnsafeRawPointer(sdlPtr).advanced(by: MemoryLayout.offset(of: \sockaddr_dl.sdl_data)!)
                    let name = String(decoding: UnsafeRawBufferPointer(start: namePtr, count: nlen), as: UTF8.self)
                    out[name] = InterfaceCounters(rx: h2.ifm_data.ifi_ibytes, tx: h2.ifm_data.ifi_obytes)
                }
                off += msgLen
            }
        }
        return out
    }
}
