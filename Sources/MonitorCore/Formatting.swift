// 纯逻辑：不依赖 Darwin/AppKit，Linux 上也能跑单测。

public enum Units {
    public static let gib: Double = 1_073_741_824   // 内存按 2^30
    public static let gb: Double = 1_000_000_000    // 磁盘按 10^9，与 Finder 一致
}

/// 菜单栏内存标题：整数 + "G"，四舍五入，例如 13.4 GiB -> "13G"。
public func formatMemoryTitle(usedBytes: UInt64) -> String {
    let g = (Double(usedBytes) / Units.gib).rounded()
    return "\(Int(max(0, g)))G"
}

/// 已用内存 = (active + wired + compressed) * pageSize。
public func usedMemoryBytes(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64) -> UInt64 {
    (active &+ wired &+ compressed) &* pageSize
}

/// 菜单栏 CPU 标题：整数百分比，例如 "23%"。
public func formatCPUTitle(percent: Int) -> String { "\(clampPercent(percent))%" }

public func clampPercent(_ p: Int) -> Int { min(100, max(0, p)) }

/// 面板里的"已用 / 总量"，保留 1 位小数，例如 "12.3 / 16.0 GB"。
public func formatUsedTotal(used: UInt64, total: UInt64, unit: Double) -> String {
    func f(_ v: UInt64) -> String {
        let x = (Double(v) / unit * 10).rounded() / 10
        let whole = Int(x)
        let frac = Int(((x - Double(whole)) * 10).rounded())
        return "\(whole).\(frac)"
    }
    return "\(f(used)) / \(f(total)) GB"
}

public func percentOf(used: UInt64, total: UInt64) -> Int {
    guard total > 0 else { return 0 }
    return clampPercent(Int((Double(used) / Double(total) * 100).rounded()))
}

/// 左侧菜单栏项标题，例如 "13G 9%"。
public func formatStatusTitle(memoryUsedBytes: UInt64, cpuPercent: Int) -> String {
    "\(formatMemoryTitle(usedBytes: memoryUsedBytes)) \(formatCPUTitle(percent: cpuPercent))"
}

/// 面板里的整数 G，例如 "12 / 16 G"。
public func formatIntG(used: UInt64, total: UInt64, unit: Double) -> String {
    "\(Int((Double(used) / unit).rounded())) / \(Int((Double(total) / unit).rounded())) G"
}
