import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// 메뉴바 서랍(⌄).
///
/// - 아이콘을 메뉴바에서 숨기는 일은 macOS 27의 시스템 설정 → 메뉴 막대 → "메뉴 막대에서 허용"이 맡는다.
///   거기서 끈 아이콘은 메뉴바와 macOS 기본 « 에서 모두 사라지지만, 앱은 계속 실행 중이라 손쉬운 사용으로는 그대로 보인다.
/// - 서랍은 다른 앱의 메뉴바 아이콘을 모두 보여주고, 누르면 그 아이콘을 손쉬운 사용으로 눌러 원래 메뉴를 연다.
/// - 끈 아이콘과 자리가 없어 « 에 숨은 아이콘은 손쉬운 사용 정보로 구별할 수 없어서(속성이 같음) 한 목록으로 보여준다.
/// - Mactatus는 아이콘을 옮기지 않는다(⌘-끌기·빈 공간 없음). 시스템 설정 값도 직접 바꾸지 않고 그 화면을 열어 준다.
@MainActor
@Observable
public final class DrawerController {
    public static let toggleLabel = "Mactatus 서랍"
    /// 시스템 설정 → 메뉴 막대
    public static let menuBarSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    public private(set) var scan: MenuBarScan?
    public private(set) var isTrusted = AXIsProcessTrusted()
    /// 사용자에게 보여줄 안내(열기 실패 등)
    public private(set) var notice: String?

    /// 서랍 패널 내용(앱이 SwiftUI 화면을 넘겨준다)
    @ObservationIgnored public var makePanelContent: (() -> AnyView)?

    @ObservationIgnored private let scanner = MenuBarScanner(toggleLabel: DrawerController.toggleLabel)
    @ObservationIgnored private let icons = MenuBarIcons()
    @ObservationIgnored private let panel = MenuBarPanel()
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults = UserDefaults.standard

    public init() {}

    // MARK: - 화면이 쓰는 값

    public var isPanelVisible: Bool { panel.isVisible }

    public func icon(for item: MenuBarItem) -> NSImage? { icons.image(for: item) }

    /// 서랍에 보여줄 아이콘: 다른 앱의 메뉴바 아이콘 전부(시스템 아이콘·Mactatus 아이콘 제외), 이름순
    public var items: [MenuBarItem] {
        (scan?.items ?? [])
            .filter { !$0.isSystem && !$0.isOwn }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - 켜기·끄기

    public func start() {
        guard statusItem == nil else { return }
        installToggle()
        observeApps()
    }

    public func stop() {
        closePanel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    /// 손쉬운 사용 권한을 묻고 시스템 설정을 연다.
    public func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 서랍 창

    public func togglePanel() {
        if panel.isVisible { closePanel(); return }
        // ⌄를 눌러 닫는 경우: 바깥 클릭 처리가 방금 닫았으니 다시 열지 않는다
        if panel.justClosedByOutsideClick { return }
        showPanel()
    }

    private func showPanel() {
        guard let content = makePanelContent?() else { return }
        let anchor = statusItem?.button?.window?.frame.maxX ?? NSEvent.mouseLocation.x
        panel.show(content: content, anchorX: anchor) {}
        // 창이 열려 있는 동안만 훑는다(닫혀 있을 때는 아무것도 하지 않음)
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.panel.isVisible else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func closePanel() {
        loop?.cancel()
        loop = nil
        notice = nil
        panel.close()
    }

    private func refresh() async {
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else { return }
        scan = await scanner.scan()
    }

    // MARK: - 동작

    /// 아이콘을 눌러 원래 메뉴를 연다(메뉴바에서 숨겨져 있어도 된다).
    public func open(_ item: MenuBarItem) {
        panel.close()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            if await !scanner.press(item) { notice = "\(item.displayName)을(를) 열지 못했어요." }
        }
    }

    /// Apple 구성 요소(입력 소스·Spotlight·날씨 등)는 종료 메뉴를 보이지 않는다.
    public func canQuit(_ item: MenuBarItem) -> Bool {
        !(item.bundleID?.hasPrefix("com.apple.") ?? true)
    }

    /// 그 앱에 종료를 요청한다(메뉴바 아이콘 우클릭의 "종료"와 같음). 서랍 목록은 다음 훑기 때 갱신된다.
    public func quit(_ item: MenuBarItem) {
        guard canQuit(item), let app = NSRunningApplication(processIdentifier: item.pid) else { return }
        if !app.terminate() { notice = "\(item.appName)을(를) 종료하지 못했어요." }
    }

    /// 그 앱을 Finder에서 보여준다.
    public func revealInFinder(_ item: MenuBarItem) {
        guard let url = NSRunningApplication(processIdentifier: item.pid)?.bundleURL else { return }
        closePanel()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 시스템 설정 → 메뉴 막대를 연다. 아이콘을 메뉴바에서 숨기거나 다시 보이게 하는 곳.
    public func openMenuBarSettings() {
        closePanel()
        NSWorkspace.shared.open(Self.menuBarSettingsURL)
    }

    // MARK: - ⌄ 버튼

    private func installToggle() {
        // 처음 만들 때만 대략 보이는 자리에 둔다(값이 클수록 왼쪽). 이후 위치는 macOS가 기억한다
        if defaults.object(forKey: "NSStatusItem Preferred Position mactatus.drawer") == nil {
            defaults.set(300.0, forKey: "NSStatusItem Preferred Position mactatus.drawer")
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "mactatus.drawer"
        item.behavior = []
        if let button = item.button {
            let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "메뉴바 서랍")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel(Self.toggleLabel)
            button.target = ToggleTarget.shared
            button.action = #selector(ToggleTarget.clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            ToggleTarget.shared.controller = self
            button.toolTip = "메뉴바 서랍"
        }
        statusItem = item
    }

    fileprivate func handleClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu(from: sender)
            return
        }
        togglePanel()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "메뉴 막대 설정 열기…", action: #selector(ToggleTarget.openSettings(_:)), keyEquivalent: "")
        settings.target = ToggleTarget.shared
        menu.addItem(settings)
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY - 4), in: button)
    }

    private func observeApps() {
        // 앱이 끝나거나 새로 켜지면 그 앱의 "아이콘 없음" 기록을 지운다(다음 훑기 때 다시 묻게)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self, let pid else { return }
                    Task { await self.scanner.forget(pid: pid) }
                }
            })
        }
    }
}

/// NSStatusBarButton의 target(약한 참조로 컨트롤러에 넘긴다).
@MainActor
private final class ToggleTarget: NSObject {
    static let shared = ToggleTarget()
    weak var controller: DrawerController?

    @objc func clicked(_ sender: NSStatusBarButton) {
        controller?.handleClick(sender)
    }

    @objc func openSettings(_ sender: Any?) {
        controller?.openMenuBarSettings()
    }
}
