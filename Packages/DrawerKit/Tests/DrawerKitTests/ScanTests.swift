import CoreGraphics
import Testing
@testable import DrawerKit

@Suite("숨김 판단")
struct ScanTests {
    @Test func collapsedAtChevronMeansHidden() {
        let chevron = CGRect(x: 872, y: 1, width: 18, height: 30)
        #expect(MenuBarScan.isCollapsed(CGRect(x: 850, y: 4, width: 40, height: 24), chevron: chevron))
        #expect(!MenuBarScan.isCollapsed(CGRect(x: 900, y: 4, width: 20, height: 24), chevron: chevron))
        #expect(!MenuBarScan.isCollapsed(CGRect(x: 850, y: 4, width: 40, height: 24), chevron: nil))
    }

    @Test func toggleHiddenWhenCollapsedOrMissing() {
        let chevron = CGRect(x: 872, y: 1, width: 18, height: 30)
        #expect(MenuBarScan(items: [], chevron: chevron, toggle: CGRect(x: 860, y: 4, width: 30, height: 24), date: .now).toggleHidden)
        #expect(!MenuBarScan(items: [], chevron: chevron, toggle: CGRect(x: 960, y: 4, width: 30, height: 24), date: .now).toggleHidden)
        #expect(MenuBarScan(items: [], chevron: nil, toggle: nil, date: .now).toggleHidden)
    }
}
