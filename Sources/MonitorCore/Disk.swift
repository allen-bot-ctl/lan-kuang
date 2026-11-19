public struct DiskUsage: Equatable {
    public var total: UInt64, available: UInt64
    public init(total: UInt64, available: UInt64) { self.total = total; self.available = available }
    public var used: UInt64 { total > available ? total - available : 0 }
    public var percent: Int { percentOf(used: used, total: total) }
    public var text: String { formatUsedTotal(used: used, total: total, unit: Units.gb) }
}
