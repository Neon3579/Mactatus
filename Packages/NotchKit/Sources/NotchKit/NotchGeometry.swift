import CoreGraphics

/// 노치 위치와 상태별 모양 크기 계산. 좌표는 Cocoa 화면 좌표(왼쪽 아래 원점).
public struct NotchGeometry: Sendable, Equatable {
    /// 하드웨어 노치
    public var notch: CGRect
    /// 노치가 있는 화면 전체
    public var screen: CGRect

    public init(notch: CGRect, screen: CGRect) {
        self.notch = notch
        self.screen = screen
    }

    /// `auxiliaryTopLeftArea`와 `auxiliaryTopRightArea` 사이가 노치다. 둘 중 하나라도 없으면 노치 없는 화면(외장 모니터 등).
    public static func make(screen: CGRect, topLeft: CGRect?, topRight: CGRect?) -> NotchGeometry? {
        guard var left = topLeft, var right = topRight, right.minX > left.maxX else { return nil }
        // 화면 기준 좌표로 오는 경우(내장 화면이 주 화면이 아닐 때)에 대비해, 화면 밖이면 화면 원점만큼 옮긴다
        if !screen.insetBy(dx: -1, dy: -1).contains(CGPoint(x: left.midX, y: left.midY)) {
            left = left.offsetBy(dx: screen.minX, dy: screen.minY)
            right = right.offsetBy(dx: screen.minX, dy: screen.minY)
        }
        let height = max(left.height, right.height)
        let notch = CGRect(x: left.maxX, y: screen.maxY - height, width: right.minX - left.maxX, height: height)
        return NotchGeometry(notch: notch, screen: screen)
    }

    /// 노치 가운데에 맞추고 위쪽 끝을 화면 위에 붙인 모양 영역.
    public func shapeFrame(_ size: CGSize) -> CGRect {
        CGRect(x: notch.midX - size.width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    /// 창 영역: 가장 큰 모양에 그림자 여유를 더한다(창 크기를 바꾸지 않고 안에서 모양만 바꾼다).
    public func panelFrame(largest: CGSize, margin: CGFloat) -> CGRect {
        shapeFrame(CGSize(width: largest.width + margin * 2, height: largest.height + margin))
    }
}
