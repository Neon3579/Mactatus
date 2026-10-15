import Foundation
import Observation

/// 시스템 리소스 메뉴바 아이콘의 모양.
public enum SystemLabelStyle: String, CaseIterable, Sendable {
    case text, graph, icon

    public var label: String {
        switch self {
        case .text: "텍스트(CPU·메모리 %)"
        case .graph: "CPU 그래프"
        case .icon: "아이콘만"
        }
    }
}

/// 앱 설정. UserDefaults에 바로 저장한다.
@MainActor
@Observable
public final class AppSettings {
    private enum Key {
        static let refreshMinutes = "usage.refreshMinutes"
        static let alertsEnabled = "usage.alertsEnabled"
        static let warnPercent = "usage.warnPercent"
        static let criticalPercent = "usage.criticalPercent"
        static let resetAlertsEnabled = "usage.resetAlertsEnabled"
        static let claudeEnabled = "usage.claude.enabled"
        static let codexEnabled = "usage.codex.enabled"
        static let geminiEnabled = "usage.gemini.enabled"
        static let claudeCLIRefresh = "usage.claude.cliRefresh"
        static let systemMenuEnabled = "system.menuEnabled"
        static let systemLabelStyle = "system.labelStyle"
        static let processCount = "system.processCount"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 사용량 조회 주기(분).
    public var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: Key.refreshMinutes) } }
    public var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) } }
    public var warnPercent: Int { didSet { defaults.set(warnPercent, forKey: Key.warnPercent) } }
    public var criticalPercent: Int { didSet { defaults.set(criticalPercent, forKey: Key.criticalPercent) } }
    public var resetAlertsEnabled: Bool { didSet { defaults.set(resetAlertsEnabled, forKey: Key.resetAlertsEnabled) } }
    public var claudeEnabled: Bool { didSet { defaults.set(claudeEnabled, forKey: Key.claudeEnabled) } }
    public var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Key.codexEnabled) } }
    public var geminiEnabled: Bool { didSet { defaults.set(geminiEnabled, forKey: Key.geminiEnabled) } }
    /// Claude 토큰이 만료됐을 때 `claude`를 백그라운드로 띄워 갱신해도 되는지.
    public var claudeCLIRefresh: Bool { didSet { defaults.set(claudeCLIRefresh, forKey: Key.claudeCLIRefresh) } }

    /// 시스템 리소스 메뉴바 아이콘을 보일지.
    public var systemMenuEnabled: Bool { didSet { defaults.set(systemMenuEnabled, forKey: Key.systemMenuEnabled) } }
    public var systemLabelStyle: SystemLabelStyle { didSet { defaults.set(systemLabelStyle.rawValue, forKey: Key.systemLabelStyle) } }
    /// 팝오버에 보여줄 CPU 상위 프로세스 수(0이면 숨김).
    public var processCount: Int { didSet { defaults.set(processCount, forKey: Key.processCount) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.refreshMinutes: 3,
            Key.alertsEnabled: true,
            Key.warnPercent: 80,
            Key.criticalPercent: 95,
            Key.resetAlertsEnabled: false,
            Key.claudeEnabled: true,
            Key.codexEnabled: true,
            Key.geminiEnabled: true,
            Key.claudeCLIRefresh: true,
            Key.systemMenuEnabled: true,
            Key.systemLabelStyle: SystemLabelStyle.text.rawValue,
            Key.processCount: 5,
        ])
        refreshMinutes = defaults.integer(forKey: Key.refreshMinutes)
        alertsEnabled = defaults.bool(forKey: Key.alertsEnabled)
        warnPercent = defaults.integer(forKey: Key.warnPercent)
        criticalPercent = defaults.integer(forKey: Key.criticalPercent)
        resetAlertsEnabled = defaults.bool(forKey: Key.resetAlertsEnabled)
        claudeEnabled = defaults.bool(forKey: Key.claudeEnabled)
        codexEnabled = defaults.bool(forKey: Key.codexEnabled)
        geminiEnabled = defaults.bool(forKey: Key.geminiEnabled)
        claudeCLIRefresh = defaults.bool(forKey: Key.claudeCLIRefresh)
        systemMenuEnabled = defaults.bool(forKey: Key.systemMenuEnabled)
        systemLabelStyle = SystemLabelStyle(rawValue: defaults.string(forKey: Key.systemLabelStyle) ?? "") ?? .text
        processCount = defaults.integer(forKey: Key.processCount)
    }
}
