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
    /// 미니 상태에서 노치 양옆 날개 하나의 폭(기본 36). 이름까지 보여주는 일시 알림은 넓게 쓴다
    var compactWingWidth: CGFloat { get }
    /// 펼친 화면에 탭으로 보일지(상태 팝업처럼 미니로만 쓰는 모듈은 false)
    var showsTab: Bool { get }
}

public extension NotchModule {
    var compactWingWidth: CGFloat { 36 }
    var showsTab: Bool { true }
}

/// 몇 초 동안만 보이는 미니 알림(연결됨·충전 중·다운로드 완료 등). 새 알림이 오면 시간을 다시 잰다.
@MainActor
@Observable
public final class NotchFlash<Value: Equatable & Sendable> {
    public private(set) var value: Value?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    public func show(_ value: Value, for duration: Duration = .seconds(3)) {
        self.value = value
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.value = nil
        }
    }

    /// 보이는 동안 내용만 바꾼다(시간은 그대로)
    public func update(_ change: (inout Value) -> Void) {
        guard var current = value else { return }
        change(&current)
        value = current
    }

    public func clear() {
        task?.cancel()
        value = nil
    }
}

/// 여러 이벤트가 겹칠 때 우선순위: 일시 알림 > 다운로드 진행 > 음악 재생 > 기본 상태(계획서 4.4).
public enum NotchPriority {
    public static let alert = 300
    public static let download = 200
    public static let media = 100
}
