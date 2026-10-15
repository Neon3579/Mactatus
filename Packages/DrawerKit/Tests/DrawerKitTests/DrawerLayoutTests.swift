import CoreGraphics
import Testing
@testable import DrawerKit

@Suite("빈 공간(구분자) 폭")
struct DrawerLayoutTests {
    @Test func growsByVisibleDrawerIconWidth() {
        // 서랍 아이콘 2개(24 + 40)가 보이면 그만큼(+4) 넓힌다
        #expect(DrawerLayout.nextSpacer(current: 10, toggleVisible: true, visibleDrawerWidth: 64, hasDrawerItems: true) == 78)
    }

    @Test func keepsWidthWhenEverythingIsHidden() {
        #expect(DrawerLayout.nextSpacer(current: 120, toggleVisible: true, visibleDrawerWidth: 0, hasDrawerItems: true) == 120)
    }

    @Test func halvesWhenToggleItselfIsHidden() {
        #expect(DrawerLayout.nextSpacer(current: 300, toggleVisible: false, visibleDrawerWidth: 40, hasDrawerItems: true) == 150)
        #expect(DrawerLayout.nextSpacer(current: 12, toggleVisible: false, visibleDrawerWidth: 0, hasDrawerItems: true) == 0)
    }

    @Test func noSpacerWhenDrawerIsEmpty() {
        #expect(DrawerLayout.nextSpacer(current: 80, toggleVisible: true, visibleDrawerWidth: 0, hasDrawerItems: false) == 0)
    }

    @Test func capsAtMaximum() {
        #expect(DrawerLayout.nextSpacer(current: 880, toggleVisible: true, visibleDrawerWidth: 100, hasDrawerItems: true) == DrawerLayout.maxSpacer)
    }
}

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
