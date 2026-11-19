import XCTest
@testable import MonitorCore

final class FormattingTests: XCTestCase {
    func testMemoryTitleRoundsAndUsesG() {
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(13.4 * Units.gib)), "13G")
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(13.6 * Units.gib)), "14G")
        XCTAssertEqual(formatMemoryTitle(usedBytes: 0), "0G")
    }
    func testUsedMemory() {
        XCTAssertEqual(usedMemoryBytes(active: 100, wired: 50, compressed: 10, pageSize: 16384), 160 * 16384)
    }
    func testCPUTitleClamps() {
        XCTAssertEqual(formatCPUTitle(percent: 23), "23%")
        XCTAssertEqual(formatCPUTitle(percent: 130), "100%")
        XCTAssertEqual(formatCPUTitle(percent: -1), "0%")
    }
    func testUsedTotal() {
        XCTAssertEqual(formatUsedTotal(used: UInt64(12.34 * Units.gib), total: UInt64(16 * Units.gib), unit: Units.gib), "12.3 / 16.0 GB")
    }
    func testPercentOfZeroTotal() { XCTAssertEqual(percentOf(used: 5, total: 0), 0) }
}

final class CPUTests: XCTestCase {
    func testDelta() {
        let a = CPUTicks(user: 100, system: 100, idle: 700, nice: 100)
        let b = CPUTicks(user: 130, system: 120, idle: 740, nice: 110)  // busy 60 / total 100
        XCTAssertEqual(cpuPercent(previous: a, current: b), 60)
    }
    func testNoChange() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(cpuPercent(previous: a, current: a), 0)
    }
    func testWraparound() {
        let a = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)  // user +20, idle +20
        XCTAssertEqual(cpuPercent(previous: a, current: b), 50)
    }
}

final class BatteryTests: XCTestCase {
    func testOverlay() {
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 30, isCharging: true, onAC: true)).overlay, .bolt)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 100, isCharging: false, onAC: true)).overlay, .plug)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 50, isCharging: false, onAC: false)).overlay, .none)
    }
    func testLowRedOnlyOnBattery() {
        XCTAssertTrue(batteryIconSpec(BatteryState(percent: 20, isCharging: false, onAC: false)).isLowRed)
        XCTAssertFalse(batteryIconSpec(BatteryState(percent: 21, isCharging: false, onAC: false)).isLowRed)
        XCTAssertFalse(batteryIconSpec(BatteryState(percent: 10, isCharging: true, onAC: true)).isLowRed)
        XCTAssertFalse(batteryIconSpec(BatteryState(percent: 10, isCharging: false, onAC: true)).isLowRed)
    }
    func testFill() {
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 87, isCharging: false, onAC: false)).fillFraction, 0.87, accuracy: 1e-9)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 150, isCharging: false, onAC: false)).fillFraction, 1.0)
    }
    func testStatusText() {
        XCTAssertEqual(batteryStatusText(BatteryState(percent: 50, isCharging: true, onAC: true)), "充电中")
        XCTAssertEqual(batteryStatusText(BatteryState(percent: 100, isCharging: false, onAC: true)), "已接电源")
        XCTAssertEqual(batteryStatusText(BatteryState(percent: 50, isCharging: false, onAC: false)), "使用电池")
        XCTAssertEqual(batteryTitle(BatteryState(percent: 87, isCharging: false, onAC: false)), "87%")
    }
    func testParse() {
        let d: [String: Any] = ["Current Capacity": 80, "Max Capacity": 100, "Is Charging": true, "Power Source State": "AC Power"]
        XCTAssertEqual(parseBattery(d), BatteryState(percent: 80, isCharging: true, onAC: true))
        XCTAssertNil(parseBattery([:]))
        let bat: [String: Any] = ["Current Capacity": 45, "Power Source State": "Battery Power"]
        XCTAssertEqual(parseBattery(bat), BatteryState(percent: 45, isCharging: false, onAC: false))
    }
}

final class StatusTitleTests: XCTestCase {
    func testCombined() {
        XCTAssertEqual(formatStatusTitle(memoryUsedBytes: UInt64(13.2 * Units.gib), cpuPercent: 9), "13G 9%")
    }
    func testIntG() {
        XCTAssertEqual(formatIntG(used: UInt64(11.6 * Units.gib), total: UInt64(16 * Units.gib), unit: Units.gib), "12 / 16 G")
    }
    func testGate() {
        var g = RefreshGate(); XCTAssertTrue(g.isActive)
        g.screenLocked = true; XCTAssertFalse(g.isActive)
        g.screenLocked = false; g.systemAsleep = true; XCTAssertFalse(g.isActive)
        g.systemAsleep = false; g.screensAsleep = true; XCTAssertFalse(g.isActive)
    }
}

final class DiskTests: XCTestCase {
    func testDisk() {
        let d = DiskUsage(total: 500_000_000_000, available: 200_000_000_000)
        XCTAssertEqual(d.used, 300_000_000_000)
        XCTAssertEqual(d.percent, 60)
        XCTAssertEqual(d.text, "300.0 / 500.0 GB")
        XCTAssertEqual(DiskUsage(total: 1, available: 5).used, 0)
    }
}
