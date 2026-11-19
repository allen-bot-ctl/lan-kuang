/// HOST_CPU_LOAD_INFO 的四个累计 tick（user/system/idle/nice）。
public struct CPUTicks: Equatable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// 两次采样之间的 CPU 占用（整数 %）。tick 是 UInt32 累计值，用 &- 处理回绕。
public func cpuPercent(previous p: CPUTicks, current c: CPUTicks) -> Int {
    let user = Double(c.user &- p.user)
    let sys = Double(c.system &- p.system)
    let idle = Double(c.idle &- p.idle)
    let nice = Double(c.nice &- p.nice)
    let total = user + sys + idle + nice
    guard total > 0 else { return 0 }
    return clampPercent(Int(((total - idle) / total * 100).rounded()))
}
