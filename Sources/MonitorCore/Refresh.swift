/// 刷新节奏（秒），集中在一处便于调。
public enum Refresh {
    public static let menuBar: Double = 2   // 菜单栏内存/CPU
    public static let panel: Double = 1     // 面板打开时
    public static let disk: Double = 60     // 面板打开时的磁盘
    public static let battery: Double = 60  // 电池兜底（主要靠 IOPS 通知）
}

/// 睡眠 / 屏幕休眠 / 锁屏时暂停全部采样。
public struct RefreshGate: Equatable {
    public var systemAsleep = false
    public var screensAsleep = false
    public var screenLocked = false
    public init() {}
    public var isActive: Bool { !(systemAsleep || screensAsleep || screenLocked) }
}

/// 面板布局常量（v0.1.1）：每行「环 · 8pt · 标签 · 弹性空白 · 数值」。
public enum PanelLayout {
    public static let width: Double = 260
    public static let horizontalPadding: Double = 12
    public static let ringDiameter: Double = 14
    public static let ringLineWidth: Double = 2
    public static let ringLabelGap: Double = 8
    /// 所有行标签的左缘 x（面板坐标）。
    public static var labelMinX: Double { horizontalPadding + ringDiameter + ringLabelGap }
    /// 所有行数值的右缘 x。
    public static var valueMaxX: Double { width - horizontalPadding }
}

/// 环形图填充比例：0% 只显示底色，100% 填满。
public func ringFraction(percent: Int) -> Double { Double(clampPercent(percent)) / 100 }

/// 布局自检：各行标签 minX 相等、数值 maxX 相等（误差 ≤ tol），且数值不越过右边距、不压到标签。
public func layoutAligned(labelMinX: [Double], labelMaxX: [Double], valueMinX: [Double], valueMaxX: [Double],
                          tol: Double = 0.5) -> Bool {
    guard let l0 = labelMinX.first, let v0 = valueMaxX.first,
          labelMinX.count == valueMaxX.count, labelMaxX.count == valueMinX.count else { return false }
    let labelsOK = labelMinX.allSatisfy { abs($0 - l0) <= tol }
    let valuesOK = valueMaxX.allSatisfy { abs($0 - v0) <= tol && $0 <= PanelLayout.valueMaxX + tol }
    let noOverlap = zip(labelMaxX, valueMinX).allSatisfy { $0 < $1 }
    return labelsOK && valuesOK && noOverlap
}
