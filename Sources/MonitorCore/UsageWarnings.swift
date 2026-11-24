import Foundation

/// 比较现有界面四舍五入后的整数百分比；只有严格超过阈值才提示。
public struct UsageWarningThresholds: Equatable {
    public static let defaultCPU = 80
    public static let defaultMemory = 90
    public static let range = 0...100
    private static let cpuKey = "usageWarning.cpuPercent"
    private static let memoryKey = "usageWarning.memoryPercent"

    public private(set) var cpu: Int
    public private(set) var memory: Int

    public init(cpu: Int = UsageWarningThresholds.defaultCPU, memory: Int = UsageWarningThresholds.defaultMemory) {
        self.cpu = clampPercent(cpu)
        self.memory = clampPercent(memory)
    }

    public func cpuWarning(_ percent: Int) -> Bool { clampPercent(percent) > cpu }

    public func memoryWarning(used: UInt64, total: UInt64) -> Bool {
        total > 0 && percentOf(used: used, total: total) > memory
    }

    public static func load(from defaults: UserDefaults) -> Self {
        func storedPercent(_ key: String, defaultValue: Int) -> Int {
            guard let value = defaults.object(forKey: key) as? Int,
                  range.contains(value) else { return defaultValue }
            return value
        }
        return Self(cpu: storedPercent(cpuKey, defaultValue: defaultCPU),
                    memory: storedPercent(memoryKey, defaultValue: defaultMemory))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(cpu, forKey: Self.cpuKey)
        defaults.set(memory, forKey: Self.memoryKey)
    }
}
