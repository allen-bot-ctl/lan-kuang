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
