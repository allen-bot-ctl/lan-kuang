import Foundation
public struct BatteryState: Equatable {
    public var percent: Int
    public var isCharging: Bool
    public var onAC: Bool
    public init(percent: Int, isCharging: Bool, onAC: Bool) {
        self.percent = percent; self.isCharging = isCharging; self.onAC = onAC
    }
}

public enum BatteryOverlay: Equatable { case bolt, plug, none }

/// 菜单栏电池图标的绘制参数：按电量填充；充电叠 ⚡，接电源未充电叠插头，用电池不叠；用电池且 ≤20% 填充变红。
public struct BatteryIconSpec: Equatable {
    public var fillFraction: Double
    public var overlay: BatteryOverlay
    public var isLowRed: Bool
}

public let batteryLowThreshold = 20

public func batteryIconSpec(_ s: BatteryState) -> BatteryIconSpec {
    let p = clampPercent(s.percent)
    let overlay: BatteryOverlay = s.isCharging ? .bolt : (s.onAC ? .plug : .none)
    return BatteryIconSpec(fillFraction: Double(p) / 100, overlay: overlay,
                           isLowRed: !s.onAC && !s.isCharging && p <= batteryLowThreshold)
}

public func batteryTitle(_ s: BatteryState) -> String { "\(clampPercent(s.percent))%" }

public func batteryStatusText(_ s: BatteryState) -> String {
    if s.isCharging { return "充电中" }
    if s.onAC { return "已接电源" }
    return "使用电池"
}

/// 从 IOPSGetPowerSourceDescription 的字典解析（键名即 IOKit 常量的字符串值，便于在 Linux 上测）。
public func parseBattery(_ d: [String: Any]) -> BatteryState? {
    guard let cur = d["Current Capacity"] as? Int else { return nil }
    let maxCap = (d["Max Capacity"] as? Int) ?? 100
    let pct = maxCap > 0 ? Int((Double(cur) / Double(maxCap) * 100).rounded()) : cur
    let charging = (d["Is Charging"] as? Bool) ?? false
    let onAC = (d["Power Source State"] as? String) == "AC Power"
    return BatteryState(percent: clampPercent(pct), isCharging: charging, onAC: onAC)
}

/// 单项菜单栏的电池图形：无电池返回 nil（不画、不留间距）。
public func batteryGlyphSpec(_ s: BatteryState?) -> BatteryIconSpec? { s.map(batteryIconSpec) }

/// 右键菜单第一行的灰色状态行；无电池返回 nil（不显示该行与分隔线）。
public func batteryMenuLine(_ s: BatteryState?) -> String? {
    guard let s else { return nil }
    return "电池 \(clampPercent(s.percent))% · \(batteryStatusText(s))"
}

/// 解析 `--debug-battery=<状态,电量>`：状态 charging / ac / battery / none。
/// 返回 .some(nil) 表示模拟无电池；格式不对返回 nil。
public func parseDebugBattery(_ arg: String) -> BatteryState?? {
    let parts = arg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let kind = parts.first else { return nil }
    if kind == "none" { return .some(nil) }
    guard parts.count == 2, let p = Int(parts[1]) else { return nil }
    switch kind {
    case "charging": return BatteryState(percent: p, isCharging: true, onAC: true)
    case "ac": return BatteryState(percent: p, isCharging: false, onAC: true)
    case "battery": return BatteryState(percent: p, isCharging: false, onAC: false)
    default: return nil
    }
}

/// 单项菜单栏布局（点）。总宽 = 左边距 + [电池 + 正极头 + 间距] + 文字列宽 + 右边距。
public enum StatusItemLayout {
    public static let sidePadding: Double = 2
    public static let glyphWidth: Double = 20
    public static let glyphHeight: Double = 10
    public static let capWidth: Double = 1.5
    public static let gap: Double = 3
    public static let fontSize: Double = 9
    public static let lineHeight: Double = 10
    public static let maxWidth: Double = 52
    public static let widestLines = ("128G", "100%")

    public static func width(textColumn: Double, hasBattery: Bool) -> Double {
        let battery = hasBattery ? glyphWidth + capWidth + gap : 0
        return (sidePadding * 2 + battery + textColumn).rounded(.up)
    }
}
