import XCTest
@testable import MonitorCore

final class FormattingTests: XCTestCase {
    func testMemoryTitleRoundsAndUsesG() {
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(13.4 * Units.gib)), "13G")
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(13.6 * Units.gib)), "14G")
        XCTAssertEqual(formatMemoryTitle(usedBytes: 0), "0G")
    }
    func testUsedMemory() {
        XCTAssertEqual(usedMemoryBytes(internalPages: 100, purgeable: 20, wired: 50, compressor: 10, pageSize: 16384), 140 * 16384)
        XCTAssertEqual(usedMemoryBytes(internalPages: 5, purgeable: 9, wired: 1, compressor: 0, pageSize: 4096), 1 * 4096)
    }
    // C2
    func testContractMemoryRounding() {
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(12.4 * Units.gib)), "12G")
        XCTAssertEqual(formatMemoryTitle(usedBytes: UInt64(12.5 * Units.gib)), "13G")
        XCTAssertFalse(formatStatusTitle(memoryUsedBytes: UInt64(12.4 * Units.gib), cpuPercent: 9).contains("GB"))
        XCTAssertFalse(formatStatusTitle(memoryUsedBytes: UInt64(12.4 * Units.gib), cpuPercent: 9).contains("."))
    }
    func testContractCPU996() {
        XCTAssertEqual(formatCPUTitle(rawPercent: 99.6), "100%")
        // tick 差：busy 996 / total 1000 = 99.6% -> 100
        let a = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 900, system: 90, idle: 4, nice: 6)
        XCTAssertEqual(formatCPUTitle(percent: cpuPercent(previous: a, current: b)), "100%")
    }
    func testUsageRow() {
        XCTAssertEqual(formatUsageRow(used: UInt64(13 * Units.gib), total: UInt64(16 * Units.gib), unit: Units.gib), "13 / 16 G · 81%")
        XCTAssertEqual(formatUsageRow(used: 412_000_000_000, total: 994_000_000_000, unit: Units.gb), "412 / 994 G · 41%")
        XCTAssertEqual(statusTitleWidest, "128G 100%")
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
    // C3：两次采样相同不除零，输出 0%
    func testNoChange() {
        let a = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        XCTAssertEqual(cpuPercent(previous: a, current: a), 0)
        XCTAssertEqual(formatCPUTitle(percent: cpuPercent(previous: a, current: a)), "0%")
    }
    func testWraparound() {
        let a = CPUTicks(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)  // user +20, idle +20
        XCTAssertEqual(cpuPercent(previous: a, current: b), 50)
    }
}

final class BatteryTests: XCTestCase {
    func testOverlay() {
        XCTAssertTrue(batteryIconSpec(BatteryState(percent: 30, isCharging: true, onAC: true)).bolt)
        XCTAssertTrue(batteryIconSpec(BatteryState(percent: 100, isCharging: false, onAC: true)).bolt)
        XCTAssertFalse(batteryIconSpec(BatteryState(percent: 50, isCharging: false, onAC: false)).bolt)
    }
    // C2：20% 用电池红，21% 不红
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

final class HoverTests: XCTestCase {
    final class Clock { var t = 0.0 }

    // C9：离开左项 → 200ms 后进入面板，面板仍显示
    func testLeaveItemThenEnterPanelWithinGrace() {
        let c = Clock(); let h = HoverDebouncer(now: { c.t })
        XCTAssertTrue(h.handle(.itemEnter))
        h.handle(.itemExit)
        c.t = 0.2; XCTAssertTrue(h.tick())
        h.handle(.panelEnter)
        c.t = 1.0; XCTAssertTrue(h.tick())
        XCTAssertNil(h.closeDeadline)
    }
    func testLeaveItemClosesAfterGrace() {
        let c = Clock(); let h = HoverDebouncer(now: { c.t })
        h.handle(.itemEnter); h.handle(.itemExit)
        c.t = 0.29; XCTAssertTrue(h.tick())
        c.t = 0.30; XCTAssertFalse(h.tick())
    }
    func testLeavePanelClosesAfterGrace() {
        let c = Clock(); let h = HoverDebouncer(now: { c.t })
        h.handle(.itemEnter); h.handle(.itemExit)
        c.t = 0.1; h.handle(.panelEnter)
        c.t = 2.0; h.handle(.panelExit)
        c.t = 2.2; XCTAssertTrue(h.tick())
        c.t = 2.31; XCTAssertFalse(h.tick())
    }
    func testReenterItemCancels() {
        let c = Clock(); let h = HoverDebouncer(now: { c.t })
        h.handle(.itemEnter); h.handle(.itemExit)
        c.t = 0.1; h.handle(.itemEnter)
        c.t = 1.0; XCTAssertTrue(h.tick())
    }
    func testClickToggles() {
        let c = Clock(); let h = HoverDebouncer(now: { c.t })
        XCTAssertTrue(h.handle(.click)); XCTAssertFalse(h.handle(.click))
    }
}

final class PanelLayoutTests: XCTestCase {
    // C2：CPU 环 0% 只显示底色，100% 填满
    func testRingFraction() {
        XCTAssertEqual(ringFraction(percent: 0), 0)
        XCTAssertEqual(ringFraction(percent: 100), 1)
        XCTAssertEqual(ringFraction(percent: 150), 1)
        XCTAssertEqual(ringFraction(percent: 41), 0.41, accuracy: 1e-9)
    }
    // C1：布局常量下三行标签同一左缘、数值右缘距面板 12pt
    func testLayoutConstants() {
        XCTAssertEqual(PanelLayout.labelMinX, 34)
        XCTAssertEqual(PanelLayout.valueMaxX, 248)
        XCTAssertEqual(PanelLayout.ringDiameter, 14)
        XCTAssertEqual(PanelLayout.ringLineWidth, 2)
    }
    func testLayoutAlignedCheck() {
        XCTAssertTrue(layoutAligned(labelMinX: [34, 34.2, 34], labelMaxX: [60, 60, 60],
                                    valueMinX: [120, 200, 110], valueMaxX: [248, 248, 247.8]))
        XCTAssertFalse(layoutAligned(labelMinX: [34, 36, 34], labelMaxX: [60, 60, 60],
                                     valueMinX: [120, 200, 110], valueMaxX: [248, 248, 248]))
        XCTAssertFalse(layoutAligned(labelMinX: [34, 34, 34], labelMaxX: [60, 60, 60],
                                     valueMinX: [120, 200, 110], valueMaxX: [248, 250, 248]))
        XCTAssertFalse(layoutAligned(labelMinX: [34, 34, 34], labelMaxX: [60, 60, 130],
                                     valueMinX: [120, 200, 110], valueMaxX: [248, 248, 248]))
    }
    // C4：最长文案
    func testLongestTexts() {
        XCTAssertEqual(formatUsageRow(used: 3_999_000_000_000, total: 4_000_000_000_000, unit: Units.gb), "3999 / 4000 G · 100%")
        XCTAssertEqual(formatUsageRow(used: UInt64(128 * Units.gib), total: UInt64(128 * Units.gib), unit: Units.gib), "128 / 128 G · 100%")
    }
}

final class SingleItemTests: XCTestCase {
    // S2：电池状态 → 图形
    func testGlyphMapping() {
        XCTAssertEqual(batteryGlyphSpec(BatteryState(percent: 18, isCharging: true, onAC: true))?.bolt, true)
        XCTAssertEqual(batteryGlyphSpec(BatteryState(percent: 100, isCharging: false, onAC: true))?.bolt, true)
        XCTAssertEqual(batteryGlyphSpec(BatteryState(percent: 20, isCharging: false, onAC: false))?.isLowRed, true)
        XCTAssertEqual(batteryGlyphSpec(BatteryState(percent: 21, isCharging: false, onAC: false))?.isLowRed, false)
        XCTAssertNil(batteryGlyphSpec(nil))
    }
    // S4：右键菜单状态行
    func testMenuLine() {
        XCTAssertEqual(batteryMenuLine(BatteryState(percent: 87, isCharging: true, onAC: true)), "电池 87% · 充电中")
        XCTAssertEqual(batteryMenuLine(BatteryState(percent: 100, isCharging: false, onAC: true)), "电池 100% · 已接电源")
        XCTAssertEqual(batteryMenuLine(BatteryState(percent: 42, isCharging: false, onAC: false)), "电池 42% · 使用电池")
        XCTAssertNil(batteryMenuLine(nil))
    }
    func testDebugBattery() {
        XCTAssertEqual(parseDebugBattery("charging,18"), .some(BatteryState(percent: 18, isCharging: true, onAC: true)))
        XCTAssertEqual(parseDebugBattery("ac,100"), .some(BatteryState(percent: 100, isCharging: false, onAC: true)))
        XCTAssertEqual(parseDebugBattery("battery,3"), .some(BatteryState(percent: 3, isCharging: false, onAC: false)))
        XCTAssertEqual(parseDebugBattery("none"), .some(nil))
        XCTAssertNil(parseDebugBattery("weird,1"))
        XCTAssertNil(parseDebugBattery("battery"))
    }
    func testBatteryPanelValue() {
        XCTAssertEqual(batteryPanelValue(BatteryState(percent: 74, isCharging: true, onAC: true)), "74% · 充电中")
        XCTAssertEqual(batteryPanelValue(BatteryState(percent: 100, isCharging: false, onAC: true)), "100% · 已接电源")
        XCTAssertEqual(batteryPanelValue(BatteryState(percent: 15, isCharging: false, onAC: false)), "15% · 使用电池")
    }
    func testWidthBudget() {
        // v0.1.3 竖电池：文字列 23pt 时带电池总宽 42pt（≤ 44pt 上限）
        XCTAssertEqual(StatusItemLayout.maxWidth, 76)
        XCTAssertEqual(StatusItemLayout.width(textColumn: 23, hasBattery: true, netColumn: 25), 65)
        XCTAssertEqual(StatusItemLayout.width(textColumn: 23, hasBattery: true), 37)
        XCTAssertEqual(StatusItemLayout.width(textColumn: 23, hasBattery: false), 23)
    }
    func testVerticalFill() {
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 50, isCharging: false, onAC: false)).fillHeight, 5, accuracy: 1e-9)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 100, isCharging: false, onAC: true)).fillHeight, 10, accuracy: 1e-9)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 1, isCharging: false, onAC: false)).fillHeight, 1, accuracy: 1e-9)
        XCTAssertEqual(batteryIconSpec(BatteryState(percent: 0, isCharging: false, onAC: false)).fillHeight, 0)
        XCTAssertEqual(StatusItemLayout.glyphHeight, 16, accuracy: 1e-9)
    }
}

final class NetworkTests: XCTestCase {
    func testFilter() {
        for n in ["en0", "en5", "en7"] { XCTAssertTrue(isPhysicalInterface(n), n) }
        for n in ["utun3", "utun5", "lo0", "awdl0", "llw0", "bridge0", "ap1", "gif0"] { XCTAssertFalse(isPhysicalInterface(n), n) }
    }
    func testDeltaSkipsUtunAndRegression() {
        // 老板 Mac 实测：下载 20MB，en7 +21.2MB，utun5 +40.5MB
        let p = ["en7": InterfaceCounters(rx: 100, tx: 50), "utun5": InterfaceCounters(rx: 0, tx: 0),
                 "en0": InterfaceCounters(rx: 5_000, tx: 0)]
        let c = ["en7": InterfaceCounters(rx: 21_189_133, tx: 1_260_091), "utun5": InterfaceCounters(rx: 40_468_532, tx: 122_507),
                 "en0": InterfaceCounters(rx: 10, tx: 0), "en9": InterfaceCounters(rx: 999, tx: 999)]
        let d = physicalDelta(previous: p, current: c)
        XCTAssertEqual(d.rx, 21_189_033)   // en0 回退记 0，en9 新出现不计，utun5 不计
        XCTAssertEqual(d.tx, 1_260_041)
        let r = netRate(previous: p, current: c, seconds: 2)
        XCTAssertEqual(r.down, 21_189_033.0 / 2, accuracy: 0.01)
        let back = netRate(previous: c, current: p, seconds: 2)
        XCTAssertEqual(back, NetRate(up: 0, down: 2495))   // 只有 en0 增长 4990B，en7 回退记 0
    }
    func testShort() {
        XCTAssertEqual(formatRateShort(0), "0B")
        XCTAssertEqual(formatRateShort(205), "205B")
        XCTAssertEqual(formatRateShort(999), "999B")
        XCTAssertEqual(formatRateShort(1000), "1.0K")
        XCTAssertEqual(formatRateShort(2150), "2.1K")
        XCTAssertEqual(formatRateShort(10 * 1024), "10K")
        XCTAssertEqual(formatRateShort(999 * 1024), "999K")
        XCTAssertEqual(formatRateShort(1000 * 1024), "1.0M")
        XCTAssertEqual(formatRateShort(10240), "10K")
        XCTAssertEqual(formatRateShort(1023 * 1024), "1.0M")
        XCTAssertEqual(formatRateShort(12 * 1024 * 1024), "12M")
        XCTAssertEqual(formatRateShort(12.3 * 1024 * 1024), "12M")
        for b in stride(from: 0.0, to: 5e9, by: 3.7e6) { XCTAssertLessThanOrEqual(formatRateShort(b).count, 4, "\(b)") }
    }
    func testFull() {
        XCTAssertEqual(formatRateFull(2150), "2.1 KB/s")
        XCTAssertEqual(formatRateFull(205), "205 B/s")
        XCTAssertEqual(formatNetRow(NetRate(up: 2150, down: 205)), "↑ 2.1 KB/s · ↓ 205 B/s")
        XCTAssertEqual(formatNetLines(NetRate(up: 2150, down: 205)).0, "↑2.1K")
    }
}

final class StickyWidthTests: XCTestCase {
    func testGrowImmediatelyShrinkAfterHold() {
        var s = StickyWidth(hold: 10)
        XCTAssertEqual(s.update(actual: 16, minimum: 16, now: 0), 16)
        XCTAssertEqual(s.update(actual: 21, minimum: 16, now: 2), 21)    // ↓205K 立即撑开
        XCTAssertEqual(s.update(actual: 19, minimum: 16, now: 4), 21)    // 变窄开始计时
        XCTAssertEqual(s.update(actual: 17, minimum: 16, now: 12), 21)   // 8 秒，不缩
        XCTAssertEqual(s.update(actual: 21, minimum: 16, now: 13), 21)   // 又变宽，计时清零
        XCTAssertEqual(s.update(actual: 12, minimum: 16, now: 14), 21)
        XCTAssertEqual(s.update(actual: 12, minimum: 16, now: 24), 16)   // 稳定 10 秒，缩回但不低于 99K 的宽度
    }
}
