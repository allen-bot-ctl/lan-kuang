// v0.1.12 卡片面板：历史缓冲、CPU 分项、翻页逻辑（纯逻辑，可在 Linux 上测）。
import Foundation

public enum CardLayout {
    public static let historyCapacity = 120          // 2 秒一个点，约 4 分钟
    public static let dotSize: Double = 6
    public static let dotSpacing: Double = 6
    public static let dotAreaHeight: Double = 14
    public static let dotBottomPadding: Double = 6
    public static let animation: Double = 0.25
    /// v0.1.14：总览加标题行（18pt，下方 6pt 间距），与其他卡片一致。
    public static let headerHeight: Double = 22      // 「设置」胶囊 22pt 高
    public static let headerGap: Double = 6
    public static let overviewBottomGap: Double = 6  // 最后一行到页码点
    /// 总览高度：标题行 + 间距 + 行数 × 22 + 行间距 4 + 上下各 10。所有卡片（含设置卡）同高。
    public static func overviewHeight(rows: Int) -> Double {
        Double(rows) * 22 + Double(max(0, rows - 1)) * 4 + 20 + 30   // 契约 C1：0.1.13 高度 + 30pt，内容顶对齐
    }
}

/// 卡片顺序：总览永远第一，没有电池不出电池卡。
public func cardIDs(hasBattery: Bool) -> [String] {
    ["overview", "mem", "cpu", "disk", "net"] + (hasBattery ? ["bat"] : [])
}

/// 定长历史：最多 capacity 个点，超出丢最旧。
/// 冷启动补点（0.1.15）：面板打开且曲线未满时临时每 25ms 采一次，约 3 秒补满；满了或面板关掉就停。
public enum FastFill {
    public static let interval: TimeInterval = 0.025
    public static func needed(cpuCount: Int, memCount: Int, capacity: Int = CardLayout.historyCapacity) -> Bool {
        min(cpuCount, memCount) < capacity
    }
}

public struct History<T>: Sequence {
    public private(set) var values: [T] = []
    public let capacity: Int
    public init(capacity: Int = CardLayout.historyCapacity) { self.capacity = capacity }
    public mutating func append(_ v: T) {
        values.append(v)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
    public var count: Int { values.count }
    public func makeIterator() -> IndexingIterator<[T]> { values.makeIterator() }
}

/// CPU 分项占比（0–100）：系统、用户（含 nice）、闲置。
public struct CPUSplit: Equatable {
    public var system: Double, user: Double, idle: Double
    public init(system: Double, user: Double, idle: Double) { self.system = system; self.user = user; self.idle = idle }
}

public func cpuSplit(previous p: CPUTicks, current c: CPUTicks) -> CPUSplit {
    let user = Double(c.user &- p.user) + Double(c.nice &- p.nice)
    let sys = Double(c.system &- p.system)
    let idle = Double(c.idle &- p.idle)
    let total = user + sys + idle
    guard total > 0 else { return CPUSplit(system: 0, user: 0, idle: 100) }
    return CPUSplit(system: sys / total * 100, user: user / total * 100, idle: idle / total * 100)
}

/// 翻页：一次手势只翻一张，到头就停不循环。
/// 触控板（有 phase）：一个手势累计超过阈值翻一页，之后到手势结束（含惯性）都不再翻。
/// 鼠标滚轮（无 phase）：每格翻一页，但两次翻页至少隔 cooldown 秒，避免一下滚过头。
public struct CardPager: Equatable {
    public enum Phase { case began, changed, ended, momentum, none }
    public private(set) var index = 0
    public private(set) var count: Int
    public let threshold: Double
    public let cooldown: Double
    private var accum = 0.0
    private var consumed = false
    private var lastFlip = -Double.infinity
    /// v0.1.14：设置卡打开时锁住翻页。
    public private(set) var settingsOpen = false
    public mutating func openSettings() { settingsOpen = true }
    /// 「‹ 返回」：关设置卡并回到总览（第 0 张）。
    public mutating func closeSettings() { settingsOpen = false; reset() }

    public init(count: Int, threshold: Double = 20, cooldown: Double = 0.3) {
        self.count = max(1, count); self.threshold = threshold; self.cooldown = cooldown
    }
    public mutating func setCount(_ n: Int) { count = max(1, n); index = min(index, count - 1) }
    public mutating func reset() { index = 0; accum = 0; consumed = false }

    /// dx/dy：scrollingDelta（向左滑/向下滚为正 = 下一张）。返回是否翻页。
    @discardableResult
    public mutating func scroll(dx: Double, dy: Double, phase: Phase, now: Double) -> Bool {
        if settingsOpen { return false }
        let d = abs(dx) >= abs(dy) ? dx : dy
        switch phase {
        case .began:
            accum = 0; consumed = false
            return step(d)
        case .changed:
            return step(d)
        case .ended:
            accum = 0; consumed = false; return false
        case .momentum:
            return false
        case .none:
            guard d != 0, now - lastFlip >= cooldown else { return false }
            if flip(d > 0 ? 1 : -1) { lastFlip = now; return true }
            return false
        }
    }

    private mutating func step(_ d: Double) -> Bool {
        guard !consumed else { return false }
        accum += d
        guard abs(accum) >= threshold else { return false }
        consumed = true
        return flip(accum > 0 ? 1 : -1)
    }

    private mutating func flip(_ dir: Int) -> Bool {
        let n = min(count - 1, max(0, index + dir))
        guard n != index else { return false }
        index = n; return true
    }
}

/// 内存卡底行：交换已用（vm.swapusage）等用 1 位小数 G。
public func formatGiB1(_ bytes: UInt64) -> String { String(format: "%.1f G", Double(bytes) / Units.gib) }
public func formatGB1(_ bytes: UInt64) -> String { String(format: "%.1f G", Double(bytes) / Units.gb) }

/// 网络卡：把 "6.4 KB/s" 拆成数字 "6.4" 和单位 "KB/s"。
public func splitRate(_ bytesPerSecond: Double) -> (number: String, unit: String) {
    let s = formatRateFull(bytesPerSecond)
    guard let i = s.firstIndex(of: " ") else { return (s, "") }
    return (String(s[..<i]), String(s[s.index(after: i)...]))
}

/// v0.1.14 右键菜单：只留三项（检查更新、设置中心、退出）。
public func contextMenuTitles(displayName: String) -> [String] { ["检查更新…", "设置中心…", "退出" + displayName] }
