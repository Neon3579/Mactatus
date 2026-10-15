import SwiftUI

/// 노치에 들어가는 기능(음악, 블루투스, 다운로드…). 각 모듈이 미니 내용·펼친 내용·우선순위를 직접 정한다.
@MainActor
public protocol NotchModule: AnyObject {
    var id: String { get }
    /// 펼친 화면의 탭 이름·아이콘
    var title: String { get }
    var symbol: String { get }
    /// 미니 상태로 보여줄 우선순위(높을수록 먼저, `NotchPriority`). nil이면 지금 보여줄 것이 없다.
    var compactPriority: Int? { get }
    /// 미니 상태: 노치 왼쪽·오른쪽 날개에 들어갈 내용
    func compactLeading() -> AnyView
    func compactTrailing() -> AnyView
    /// 펼친 상태의 내용
    func expanded() -> AnyView
}

/// 여러 이벤트가 겹칠 때 우선순위: 일시 알림 > 다운로드 진행 > 음악 재생 > 기본 상태(계획서 4.4).
public enum NotchPriority {
    public static let alert = 300
    public static let download = 200
    public static let media = 100
}
