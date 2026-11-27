import XCTest
@testable import MonitorCore

final class SettingsLayoutTests: XCTestCase {
    func testContentHeightFitsAllFiveRows() {
        XCTAssertEqual(SettingsLayout.contentHeight, 204)
        // 比总览高（有电池 5 行 176，没电池 4 行 150），所以设置卡必须变高
        XCTAssertGreaterThan(SettingsLayout.contentHeight, CardLayout.overviewHeight(rows: 5))
        XCTAssertGreaterThan(SettingsLayout.contentHeight, CardLayout.overviewHeight(rows: 4))
    }

    func testHeightFollowsContentWhenScreenFits() {
        for rows in [4, 5] {
            let ov = CardLayout.overviewHeight(rows: rows)
            for available: Double? in [nil, 204, 600, 1200] {
                let h = SettingsLayout.cardHeight(overview: ov, available: available)
                XCTAssertEqual(h, SettingsLayout.contentHeight)
                XCTAssertFalse(SettingsLayout.needsScroll(cardHeight: h))
            }
        }
    }

    func testScrollFallbackOnlyWhenScreenTooShort() {
        let ov = CardLayout.overviewHeight(rows: 5)
        let h = SettingsLayout.cardHeight(overview: ov, available: 190)
        XCTAssertEqual(h, 190)
        XCTAssertTrue(SettingsLayout.needsScroll(cardHeight: h))
        // 再矮也不比总览矮
        XCTAssertEqual(SettingsLayout.cardHeight(overview: ov, available: 80), ov)
    }

    func testOverviewPanelHeightUnchangedFrom0118() {
        XCTAssertEqual(CardLayout.overviewHeight(rows: 5) + CardLayout.dotsHeight, 196)
        XCTAssertEqual(CardLayout.overviewHeight(rows: 4) + CardLayout.dotsHeight, 170)
    }
}
