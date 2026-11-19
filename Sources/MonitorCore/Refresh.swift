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
