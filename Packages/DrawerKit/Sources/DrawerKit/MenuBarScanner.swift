// 비공식: macOS 27에서는 메뉴바 아이콘을 MenuBarAgent가 그리므로 창 목록(CGWindowList)으로 찾을 수 없다.
// 앱마다 손쉬운 사용의 AXExtrasMenuBar로 읽고, MenuBarAgent의 AXButton을 기본 « 버튼으로 본다.
// macOS 27.0.1에서 확인(docs/spike-results.md 7번, 3단계 재검증).
import AppKit
import ApplicationServices

// MARK: - AX 도우미

func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    axValue(element, attribute) as? String
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = axValue(element, kAXPositionAttribute), let size = axValue(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero
    var extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func axLabel(_ element: AXUIElement) -> String {
    for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute] {
        if let text = axString(element, attribute), !text.isEmpty { return text }
    }
    return ""
}

/// 앱의 메뉴바 아이콘 요소들.
func extrasElements(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    guard let bar = axValue(app, "AXExtrasMenuBar") else { return [] }
    return axValue(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

// MARK: - 훑기

/// 메인 스레드 밖에서 모든 앱의 메뉴바 아이콘을 읽는다.
actor MenuBarScanner {
    /// 메뉴바 아이콘이 없던 앱은 60초 동안 다시 묻지 않는다(앱마다 AX 질의 비용이 있어서).
    private var emptyApps: [pid_t: Date] = [:]
    private let toggleLabel: String

    init(toggleLabel: String) {
        self.toggleLabel = toggleLabel
    }

    func forget(pid: pid_t) {
        emptyApps[pid] = nil
    }

    func scan() -> MenuBarScan {
        let me = ProcessInfo.processInfo.processIdentifier
        let now = Date()
        var raw: [(MenuBarItem, CGRect)] = []
        var chevron: CGRect?
        var toggle: CGRect?

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            if let checked = emptyApps[pid], now.timeIntervalSince(checked) < 60 { continue }
            let elements = extrasElements(pid: pid)
            guard !elements.isEmpty else {
                emptyApps[pid] = now
                continue
            }
            let bundle = app.bundleIdentifier
            for (index, element) in elements.enumerated() {
                guard let frame = axFrame(element) else { continue }
                if bundle == "com.apple.MenuBarAgent", axString(element, kAXRoleAttribute) == kAXButtonRole {
                    chevron = frame
                    continue
                }
                let label = axLabel(element)
                if pid == me, label == toggleLabel {
                    toggle = frame
                    continue
                }
                let item = MenuBarItem(
                    key: "\(bundle ?? app.localizedName ?? "pid\(pid)")#\(index)",
                    pid: pid, bundleID: bundle, appName: app.localizedName ?? "앱",
                    title: label, index: index, frame: frame, isHidden: false,
                    isOwn: pid == me, isSystem: bundle.map(MenuBarItem.systemBundles.contains) ?? false)
                raw.append((item, frame))
            }
        }
        emptyApps = emptyApps.filter { pid, _ in NSRunningApplication(processIdentifier: pid) != nil }

        let items = raw.map { item, frame in
            MenuBarItem(key: item.key, pid: item.pid, bundleID: item.bundleID, appName: item.appName, title: item.title,
                        index: item.index, frame: frame, isHidden: MenuBarScan.isCollapsed(frame, chevron: chevron),
                        isOwn: item.isOwn, isSystem: item.isSystem)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
        return MenuBarScan(items: items, chevron: chevron, toggle: toggle, date: now)
    }

    /// 다른 앱의 아이콘을 누른다(그 앱의 메뉴·창이 원래 자리에 열린다). 숨겨져 있어도 된다.
    func press(_ item: MenuBarItem) -> Bool {
        let elements = extrasElements(pid: item.pid)
        guard item.index < elements.count else { return false }
        return AXUIElementPerformAction(elements[item.index], kAXPressAction as CFString) == .success
    }
}
