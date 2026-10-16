import CoreGraphics
import Foundation

/// 메뉴바 아이콘 하나(다른 앱 것 포함). 좌표는 CG(왼쪽 위 원점).
public struct MenuBarItem: Identifiable, Sendable, Hashable {
    /// "번들ID#앱 안의 순번" — 아이콘을 옮겨도 바뀌지 않는다.
    public let key: String
    public var id: String { key }
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    /// 손쉬운 사용으로 읽은 제목·설명(없을 수 있음)
    public let title: String
    public let index: Int
    public let frame: CGRect
    /// macOS 기본 « 안에 숨겨져 있는지
    public let isHidden: Bool
    /// Mactatus 자신의 아이콘(AI·시스템 아이콘)
    public let isOwn: Bool
    /// Wi-Fi·배터리·시계처럼 옮길 수 없는 시스템 아이콘
    public let isSystem: Bool

    public init(key: String, pid: pid_t, bundleID: String?, appName: String, title: String, index: Int,
                frame: CGRect, isHidden: Bool, isOwn: Bool, isSystem: Bool) {
        self.key = key
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.index = index
        self.frame = frame
        self.isHidden = isHidden
        self.isOwn = isOwn
        self.isSystem = isSystem
    }

    public var displayName: String {
        if let bundleID, let known = Self.knownNames[bundleID] { return known }
        var text = title
        // "Gemini status menu" → "Gemini"
        if text.lowercased().hasSuffix(" status menu") { text = String(text.dropLast(" status menu".count)) }
        if !text.isEmpty, text != "-" { return text }
        return isSystem ? "시스템" : appName
    }

    /// 제목이 없거나 내부 이름만 있는 시스템 아이콘의 보기 좋은 이름.
    static let knownNames = [
        "com.apple.TextInputMenuAgent": "입력 소스",
        "com.apple.weather.menu": "날씨",
    ]

    static let systemBundles: Set<String> = ["com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.controlcenter"]
}

/// 한 번 훑은 결과.
public struct MenuBarScan: Sendable, Equatable {
    /// ⌄ 버튼과 « 를 뺀 모든 아이콘
    public var items: [MenuBarItem]
    /// macOS 기본 « 버튼(숨겨진 아이콘이 있을 때만)
    public var chevron: CGRect?
    /// 우리 ⌄ 버튼(왼쪽 빈 공간 포함)
    public var toggle: CGRect?
    public var date: Date

    /// ⌄ 버튼이 « 안으로 숨겨졌는지(보이는 아이콘이 너무 많을 때)
    public var toggleHidden: Bool {
        guard let toggle else { return true }
        return MenuBarScan.isCollapsed(toggle, chevron: chevron)
    }

    /// « 에 겹쳐 있으면 숨겨진 것.
    static func isCollapsed(_ frame: CGRect, chevron: CGRect?) -> Bool {
        guard let chevron else { return false }
        return frame.maxX <= chevron.maxX + 2
    }
}
