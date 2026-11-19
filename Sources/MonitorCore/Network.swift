import Foundation
// 网速：只统计物理网卡 en*（有线、Wi-Fi），跳过 utun*（Clash TUN 等会把同一份流量再算一遍）、lo0、awdl*、llw*、bridge*、ap*。
// 老板 Mac 实测（2026-11-19）：下载 20MB，en7 计 21.2MB，utun5 计 40.5MB。

public func isPhysicalInterface(_ name: String) -> Bool { name.hasPrefix("en") }

/// 某块网卡的累计字节（NET_RT_IFLIST2 的 if_data64）。
public struct InterfaceCounters: Equatable {
    public var rx: UInt64
    public var tx: UInt64
    public init(rx: UInt64, tx: UInt64) { self.rx = rx; self.tx = tx }
}

/// 两次采样之间物理网卡的总增量（字节）。新出现的网卡本轮不计；计数变小（重置、换网）这一轮记 0。
public func physicalDelta(previous: [String: InterfaceCounters], current: [String: InterfaceCounters]) -> (rx: UInt64, tx: UInt64) {
    var rx: UInt64 = 0, tx: UInt64 = 0
    for (name, c) in current where isPhysicalInterface(name) {
        guard let p = previous[name] else { continue }
        if c.rx >= p.rx { rx += c.rx - p.rx }
        if c.tx >= p.tx { tx += c.tx - p.tx }
    }
    return (rx, tx)
}

public struct NetRate: Equatable {
    public var up: Double    // 字节/秒
    public var down: Double
    public init(up: Double, down: Double) { self.up = up; self.down = down }
}

public func netRate(previous: [String: InterfaceCounters], current: [String: InterfaceCounters], seconds: Double) -> NetRate {
    guard seconds > 0 else { return NetRate(up: 0, down: 0) }
    let d = physicalDelta(previous: previous, current: current)
    return NetRate(up: Double(d.tx) / seconds, down: Double(d.rx) / seconds)
}

/// 菜单栏短格式（不带 /s）：B、K、M，按 1024 进位。<10 一位小数，≥10 取整；最长 4 个字符，如 "999K"、"2.1K"、"205B"、"12M"。
public func formatRateShort(_ bytesPerSecond: Double) -> String {
    let b = max(0, bytesPerSecond)
    if b < 1000 { return "\(Int(b.rounded()))B" }
    var v = b / 1024
    for unit in ["K", "M", "G"] {
        let shown = v < 9.95 ? (v * 10).rounded() / 10 : v.rounded()
        if shown < 1000 || unit == "G" {
            if shown < 10 { return String(format: "%.1f", shown) + unit }
            return "\(Int(min(shown, 999)))" + unit
        }
        v /= 1024
    }
    return "999G"
}

/// 面板完整格式："2.1 KB/s"、"205 B/s"、"12 MB/s"。
public func formatRateFull(_ bytesPerSecond: Double) -> String {
    let s = formatRateShort(bytesPerSecond)
    guard let unit = s.last else { return s }
    let num = s.dropLast()
    return "\(num) \(unit == "B" ? "" : String(unit))B/s"
}

/// 面板「网络」行："↑ 2.1 KB/s · ↓ 205 B/s"。
public func formatNetRow(_ r: NetRate) -> String { "↑ \(formatRateFull(r.up)) · ↓ \(formatRateFull(r.down))" }

/// 菜单栏第三列两行：上行、下行。
public func formatNetLines(_ r: NetRate) -> (String, String) { ("↑" + formatRateShort(r.up), "↓" + formatRateShort(r.down)) }

/// 第三列定宽用的最长文案。
public let netWidestLines = ("↑999K", "↓999K")
