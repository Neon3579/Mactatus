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
        static let drawerEnabled = "drawer.enabled"
        static let notchEnabled = "notch.enabled"
        static let mediaEnabled = "notch.media.enabled"
        static let bluetoothEnabled = "notch.bluetooth.enabled"
        static let downloadsEnabled = "notch.downloads.enabled"
        static let statusEnabled = "notch.status.enabled"
        static let statusVolumeEnabled = "notch.status.volume"
        static let trayEnabled = "notch.tray.enabled"
        static let trayKeepsCopies = "notch.tray.keepsCopies"
        static let trayClearHours = "notch.tray.clearHours"
        static let screenshotEnabled = "notch.screenshot.enabled"
        static let clipboardEnabled = "notch.clipboard.enabled"
        static let clipboardLimit = "notch.clipboard.limit"
        static let clipboardHotkey = "notch.clipboard.hotkey"
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

    /// 메뉴바 서랍(⌄ 버튼)을 쓸지.
    public var drawerEnabled: Bool { didSet { defaults.set(drawerEnabled, forKey: Key.drawerEnabled) } }

    /// 노치 허브를 쓸지(내장 디스플레이에만 뜬다).
    public var notchEnabled: Bool { didSet { defaults.set(notchEnabled, forKey: Key.notchEnabled) } }
    /// 노치에 지금 재생 중인 음악을 보일지.
    public var mediaEnabled: Bool { didSet { defaults.set(mediaEnabled, forKey: Key.mediaEnabled) } }
    /// 블루투스 기기 연결·끊김 알림
    public var bluetoothEnabled: Bool { didSet { defaults.set(bluetoothEnabled, forKey: Key.bluetoothEnabled) } }
    /// 다운로드 진행·완료
    public var downloadsEnabled: Bool { didSet { defaults.set(downloadsEnabled, forKey: Key.downloadsEnabled) } }
    /// 상태 팝업(충전·저전력·Caps Lock)
    public var statusEnabled: Bool { didSet { defaults.set(statusEnabled, forKey: Key.statusEnabled) } }
    /// 볼륨 팝업(macOS 기본 볼륨 팝업도 함께 떠서 기본은 끔)
    public var statusVolumeEnabled: Bool { didSet { defaults.set(statusVolumeEnabled, forKey: Key.statusVolumeEnabled) } }
    /// 파일 트레이
    public var trayEnabled: Bool { didSet { defaults.set(trayEnabled, forKey: Key.trayEnabled) } }
    /// 원본 대신 복사본을 보관할지
    public var trayKeepsCopies: Bool { didSet { defaults.set(trayKeepsCopies, forKey: Key.trayKeepsCopies) } }
    /// 담은 지 이 시간이 지나면 트레이에서 뺀다(0이면 안 뺌)
    public var trayClearHours: Int { didSet { defaults.set(trayClearHours, forKey: Key.trayClearHours) } }
    /// 새 스크린샷 알림
    public var screenshotEnabled: Bool { didSet { defaults.set(screenshotEnabled, forKey: Key.screenshotEnabled) } }
    /// 클립보드 기록(복사한 글·이미지·파일과 새 스크린샷). 켜면 macOS가 붙여넣기 허용을 물을 수 있다
    public var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled) } }
    /// 고정하지 않은 기록을 몇 개까지 남길지
    public var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: Key.clipboardLimit) } }
    /// ⌘⇧V로 기록 창 열기
    public var clipboardHotkeyEnabled: Bool { didSet { defaults.set(clipboardHotkeyEnabled, forKey: Key.clipboardHotkey) } }

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
            // 노치 오른쪽 자리가 좁아 기본은 그래프(약 44pt). 숫자 두 개(text)는 약 116pt
            Key.systemLabelStyle: SystemLabelStyle.graph.rawValue,
            Key.processCount: 5,
            Key.drawerEnabled: true,
            Key.notchEnabled: true,
            Key.mediaEnabled: true,
            Key.bluetoothEnabled: true,
            Key.downloadsEnabled: true,
            Key.statusEnabled: true,
            Key.statusVolumeEnabled: false,
            Key.trayEnabled: true,
            Key.trayKeepsCopies: false,
            Key.trayClearHours: 24,
            Key.screenshotEnabled: true,
            Key.clipboardEnabled: true,
            Key.clipboardLimit: 50,
            Key.clipboardHotkey: true,
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
        systemLabelStyle = SystemLabelStyle(rawValue: defaults.string(forKey: Key.systemLabelStyle) ?? "") ?? .graph
        processCount = defaults.integer(forKey: Key.processCount)
        drawerEnabled = defaults.bool(forKey: Key.drawerEnabled)
        notchEnabled = defaults.bool(forKey: Key.notchEnabled)
        mediaEnabled = defaults.bool(forKey: Key.mediaEnabled)
        bluetoothEnabled = defaults.bool(forKey: Key.bluetoothEnabled)
        downloadsEnabled = defaults.bool(forKey: Key.downloadsEnabled)
        statusEnabled = defaults.bool(forKey: Key.statusEnabled)
        statusVolumeEnabled = defaults.bool(forKey: Key.statusVolumeEnabled)
        trayEnabled = defaults.bool(forKey: Key.trayEnabled)
        trayKeepsCopies = defaults.bool(forKey: Key.trayKeepsCopies)
        trayClearHours = defaults.integer(forKey: Key.trayClearHours)
        screenshotEnabled = defaults.bool(forKey: Key.screenshotEnabled)
        clipboardEnabled = defaults.bool(forKey: Key.clipboardEnabled)
        clipboardLimit = defaults.integer(forKey: Key.clipboardLimit)
        clipboardHotkeyEnabled = defaults.bool(forKey: Key.clipboardHotkey)
    }
}
