import Foundation
import XCTest
@testable import MonitorCore

final class UsageWarningsTests: XCTestCase {
    func testDefaultsAndExactThresholdDoNotWarn() {
        let thresholds = UsageWarningThresholds()
        XCTAssertEqual(thresholds.cpu, 80)
        XCTAssertEqual(thresholds.memory, 90)
        XCTAssertFalse(thresholds.cpuWarning(80))
        XCTAssertTrue(thresholds.cpuWarning(81))
        XCTAssertFalse(thresholds.memoryWarning(used: 90, total: 100))
        XCTAssertFalse(thresholds.memoryWarning(used: 904, total: 1000))
        XCTAssertTrue(thresholds.memoryWarning(used: 905, total: 1000))
        XCTAssertFalse(thresholds.memoryWarning(used: 100, total: 0))
    }

    func testScreenshotCaseAndIndependentCustomLimits() {
        let defaults = UsageWarningThresholds()
        XCTAssertFalse(defaults.cpuWarning(41))
        XCTAssertFalse(defaults.memoryWarning(used: 13, total: 16))
        XCTAssertFalse(defaults.memoryWarning(used: 14, total: 16))
        XCTAssertTrue(UsageWarningThresholds(cpu: 80, memory: 80).memoryWarning(used: 13, total: 16))
        let custom = UsageWarningThresholds(cpu: 40, memory: 81)
        XCTAssertTrue(custom.cpuWarning(41))
        XCTAssertFalse(custom.memoryWarning(used: 13, total: 16))
    }

    func testRangeEndpoints() {
        let thresholds = UsageWarningThresholds(cpu: -1, memory: 101)
        XCTAssertEqual(thresholds.cpu, 0)
        XCTAssertEqual(thresholds.memory, 100)
        XCTAssertFalse(thresholds.cpuWarning(0))
        XCTAssertTrue(thresholds.cpuWarning(1))
        XCTAssertFalse(thresholds.memoryWarning(used: 100, total: 100))
    }

    func testSettingsPersistAndInvalidValuesFallBackPerMetric() throws {
        let name = "com.lankuang.tests.usage-warning.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(UsageWarningThresholds.load(from: defaults), .init())
        UsageWarningThresholds(cpu: 0, memory: 92).save(to: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        XCTAssertEqual(UsageWarningThresholds.load(from: reopened), .init(cpu: 0, memory: 92))
        reopened.set("bad", forKey: "usageWarning.memoryPercent")
        XCTAssertEqual(UsageWarningThresholds.load(from: reopened), .init(cpu: 0, memory: 90))
        reopened.set(101, forKey: "usageWarning.cpuPercent")
        XCTAssertEqual(UsageWarningThresholds.load(from: reopened), .init(cpu: 80, memory: 90))
    }
}
