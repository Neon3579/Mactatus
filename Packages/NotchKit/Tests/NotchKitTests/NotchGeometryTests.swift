import CoreGraphics
import Testing
@testable import NotchKit

@Suite("노치 위치 계산")
struct NotchGeometryTests {
    // MacBook Air M2(1470×956)에서 확인한 값: 노치 x 645.5, 폭 179, 높이 32
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    let left = CGRect(x: 0, y: 924, width: 645.5, height: 32)
    let right = CGRect(x: 824.5, y: 924, width: 645.5, height: 32)

    @Test func notchBetweenAuxiliaryAreas() throws {
        let geometry = try #require(NotchGeometry.make(screen: screen, topLeft: left, topRight: right))
        #expect(geometry.notch == CGRect(x: 645.5, y: 924, width: 179, height: 32))
    }

    @Test func screenRelativeAreasAreMovedOntoScreen() throws {
        // 외장 모니터가 주 화면이라 내장 화면 원점이 (1920, 100)인 경우
        let moved = CGRect(x: 1920, y: 100, width: 1470, height: 956)
        let geometry = try #require(NotchGeometry.make(screen: moved, topLeft: left, topRight: right))
        #expect(geometry.notch == CGRect(x: 2565.5, y: 1024, width: 179, height: 32))
    }

    @Test func noNotchWithoutAuxiliaryAreas() {
        #expect(NotchGeometry.make(screen: screen, topLeft: nil, topRight: right) == nil)
        #expect(NotchGeometry.make(screen: screen, topLeft: left, topRight: nil) == nil)
    }

    @Test func shapeIsCenteredAndTouchesTop() throws {
        let geometry = try #require(NotchGeometry.make(screen: screen, topLeft: left, topRight: right))
        let frame = geometry.shapeFrame(CGSize(width: 500, height: 178))
        #expect(frame.midX == geometry.notch.midX)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func panelAddsMarginOnSidesAndBottom() throws {
        let geometry = try #require(NotchGeometry.make(screen: screen, topLeft: left, topRight: right))
        let panel = geometry.panelFrame(largest: CGSize(width: 500, height: 178), margin: 24)
        #expect(panel.width == 548)
        #expect(panel.height == 202)
        #expect(panel.maxY == screen.maxY)
    }
}
