import CoreGraphics

/// ⌄ 버튼 왼쪽 빈 공간(구분자) 폭 계산.
///
/// macOS 27은 메뉴바에 자리가 모자라면 아이콘을 노치 왼쪽 빈 곳으로, 거기도 없으면 « 안으로 보낸다.
/// 서랍 아이콘을 « 로 보내려면 ⌄ 왼쪽 빈 공간으로 남는 자리를 채우면 된다. 그래서 서랍 아이콘이
/// 보이면 그 폭만큼 넓히고, ⌄ 자신이 숨겨질 만큼 넓어지면 반으로 줄인다(그 폭은 호출하는 쪽이 상한으로 기억).
public enum DrawerLayout {
    public static let maxSpacer: CGFloat = 900

    /// - Parameters:
    ///   - current: 지금 빈 공간 폭
    ///   - toggleVisible: ⌄가 메뉴바에 보이는지(노치 왼쪽이어도 보이면 true)
    ///   - visibleDrawerWidth: 서랍 아이콘인데 메뉴바에 보이는 것들의 폭 합
    ///   - hasDrawerItems: 서랍 아이콘이 하나라도 있는지
    public static func nextSpacer(current: CGFloat, toggleVisible: Bool, visibleDrawerWidth: CGFloat, hasDrawerItems: Bool) -> CGFloat {
        guard toggleVisible else { return current >= 20 ? (current / 2).rounded(.down) : 0 }
        guard hasDrawerItems else { return 0 }
        guard visibleDrawerWidth > 0 else { return current }
        return min(current + visibleDrawerWidth + 4, maxSpacer).rounded()
    }
}
