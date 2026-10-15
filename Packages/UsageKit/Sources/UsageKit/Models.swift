import Foundation

public enum ProviderID: String, Sendable, CaseIterable, Identifiable {
    case claude, codex, gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini"
        }
    }
}

/// 한도 창 하나(예: 5시간 세션, 주간).
public struct UsageWindow: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    /// 사용한 비율(0~100).
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }
}

/// 한 서비스의 사용량 조회 결과.
public struct UsageSnapshot: Sendable, Equatable {
    public var provider: ProviderID
    /// 실제로 읽은 곳(예: "Antigravity").
    public var source: String
    public var plan: String?
    public var windows: [UsageWindow]
    public var notes: [String]
    public var fetchedAt: Date

    public init(provider: ProviderID, source: String, plan: String?, windows: [UsageWindow], notes: [String] = [], fetchedAt: Date = Date()) {
        self.provider = provider
        self.source = source
        self.plan = plan
        self.windows = windows
        self.notes = notes
        self.fetchedAt = fetchedAt
    }

    public var mostConstrained: UsageWindow? { windows.max { $0.usedPercent < $1.usedPercent } }
}

/// 조회가 안 될 때 화면에 보여줄 이유.
public struct UsageIssue: Error, Sendable, Equatable, LocalizedError {
    public enum Kind: Sendable, Equatable {
        /// 설치·로그인이 안 됨 — 사용자가 이 서비스를 안 쓸 가능성이 큼
        case notConfigured
        /// 사용자가 무언가 하면 해결됨(예: 앱 켜기)
        case needsAction
        /// 지원이 끝난 경로
        case unsupported
        /// 네트워크 연결·시간 초과(다음 조회 때 저절로 풀릴 가능성이 큼)
        case network
        /// 그 밖의 실패(응답 형식이 바뀜 등)
        case failed
    }

    public var kind: Kind
    public var message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }

    public static func failed(_ message: String) -> UsageIssue { .init(.failed, message) }
    public static func network(_ message: String) -> UsageIssue { .init(.network, message) }
    public static func needsAction(_ message: String) -> UsageIssue { .init(.needsAction, message) }
    public static func notConfigured(_ message: String) -> UsageIssue { .init(.notConfigured, message) }
    public static func unsupported(_ message: String) -> UsageIssue { .init(.unsupported, message) }
}

/// 화면이 쓰는 서비스별 상태.
public struct ProviderState: Sendable, Equatable {
    /// 마지막으로 성공한 결과(실패해도 남겨 둔다).
    public var snapshot: UsageSnapshot?
    public var issue: UsageIssue?
    public var isLoading = false
    public var lastAttempt: Date?

    public init() {}
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// 실패하면 `UsageIssue`를 던진다.
    func fetch() async throws -> UsageSnapshot
}
