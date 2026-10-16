import AppKit
import DrawerKit
import SwiftUI

/// 직접 만드는 메뉴바 아이템: SwiftUI 라벨 + 누르면 아래에 열리는 창.
///
/// SwiftUI `MenuBarExtra`는 아이템 이름(autosaveName)을 정할 수 없어서, macOS 27에서 처음 놓일 자리를 고를 수 없다
/// (서랍 ⌄ 왼쪽에 놓이면 « 안으로 숨고, 숨은 아이콘은 끌어 옮길 수도 없다).
/// 이름을 직접 정하고 처음 만들 때 위치값(`NSStatusItem Preferred Position <이름>`, 화면 오른쪽 끝에서 잰 거리)을 주어
/// ⌄ 오른쪽, 즉 메뉴바에 남는 쪽에 놓이게 한다. macOS 27.0.1에서 확인.
@MainActor
final class StatusItemHost: NSObject {
    private let baseName: String
    private let title: String
    private let label: () -> AnyView
    private let content: () -> AnyView
    private let panel = MenuBarPanel()
    private let defaults = UserDefaults.standard
    private var item: NSStatusItem?
    private var labelView: StatusLabelView?

    /// - Parameters:
    ///   - name: 아이템 이름(autosaveName)의 앞부분
    ///   - title: 손쉬운 사용 이름
    init(name: String, title: String, label: @escaping () -> AnyView, content: @escaping () -> AnyView) {
        baseName = name
        self.title = title
        self.label = label
        self.content = content
    }

    var isInstalled: Bool { item != nil }

    // MARK: - 이름과 위치값

    /// 다시 만들 때마다 이름을 바꾼다(macOS가 기억하는 예전 자리 대신 새 위치값으로 놓이게).
    private var generationKey: String { "statusItem.\(baseName).generation" }
    private var name: String {
        let generation = defaults.integer(forKey: generationKey)
        return generation == 0 ? baseName : "\(baseName).\(generation)"
    }
    private func positionKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    // MARK: - 넣기·빼기

    /// 메뉴바에 넣는다. `position`(작을수록 오른쪽)은 이 이름으로 처음 놓일 때만 쓴다.
    func install(position: CGFloat?) {
        guard item == nil else { return }
        let name = self.name
        if let position, defaults.object(forKey: positionKey(name)) == nil {
            defaults.set(Double(position.rounded()), forKey: positionKey(name))
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.setAccessibilityLabel(title)
            button.target = self
            button.action = #selector(clicked(_:))
            // 라벨 폭이 바뀌면(숫자가 늘거나 자료가 처음 들어올 때) 아이템 폭을 맞춘다
            let view = StatusLabelView(rootView: AnyView(label()
                .font(.system(size: NSFont.menuBarFont(ofSize: 0).pointSize))
                .fixedSize()
                .padding(.horizontal, 5)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { [weak self] width in
                    self?.setLength(width)
                }
                .frame(maxHeight: .infinity)))
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            labelView = view
        }
        self.item = item
        if let labelView { setLength(labelView.fittingSize.width) }
    }

    func uninstall() {
        panel.close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
        labelView = nil
    }

    private func setLength(_ width: CGFloat) {
        guard let item, width > 0 else { return }
        let length = ceil(width)
        if item.length != length { item.length = length }
    }

    // MARK: - 창

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if panel.isVisible { panel.close(); return }
        // 이 아이콘을 눌러 닫는 경우: 바깥 클릭 처리가 방금 닫았으니 다시 열지 않는다
        if panel.justClosedByOutsideClick { return }
        guard let frame = sender.window?.frame else { return }
        panel.show(content: content(), anchorX: frame.minX, edge: .leading) { [weak self] in
            guard let self else { return }
            self.item?.button?.highlight(self.panel.isVisible)
        }
    }

    func closePanel() { panel.close() }
}

/// 메뉴바 버튼 위에 SwiftUI 라벨을 그린다. 클릭은 아래 버튼이 받는다.
private final class StatusLabelView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 팝오버의 "설정…" 버튼이 부르는 동작. SwiftUI `openSettings`는 장면(Scene) 안에서만 동작해서 직접 넘겨준다.
struct OpenAppSettingsAction: Sendable {
    let run: @MainActor @Sendable () -> Void

    @MainActor func callAsFunction() { run() }
}

extension EnvironmentValues {
    @Entry var openAppSettings = OpenAppSettingsAction(run: {})
}

/// 설정 창(메뉴바 아이템을 직접 만들면서 SwiftUI `Settings` 장면 대신 쓴다).
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(makeContent: @escaping () -> AnyView) {
        self.makeContent = makeContent
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
            window.title = "Mactatus 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
