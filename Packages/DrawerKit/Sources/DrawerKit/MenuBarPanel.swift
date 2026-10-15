import AppKit
import SwiftUI

/// 메뉴바 아이콘 아래에 뜨는 창(서랍, AI 사용량, 시스템 리소스 공통). 바깥을 누르거나 Esc를 누르면 닫힌다.
@MainActor
public final class MenuBarPanel {
    /// 창을 아이콘의 어느 끝에 맞출지
    public enum Edge: Sendable { case leading, trailing }

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var onChange: (() -> Void)?
    private var anchor: (x: CGFloat, edge: Edge) = (0, .trailing)

    public init() {}

    public var isVisible: Bool { panel?.isVisible ?? false }
    /// 패널 위치(Cocoa 화면 좌표)
    public var frame: NSRect? { panel?.frame }
    /// true면 바깥을 눌러도 닫히지 않는다(편집 모드)
    public var keepOpen = false
    /// Esc를 눌렀을 때(없으면 그냥 닫는다)
    public var onEscape: (() -> Void)?
    /// 바깥 클릭으로 막 닫혔는지. 아이콘을 눌러 닫을 때 바깥 클릭 처리가 먼저 닫아 버리므로,
    /// 이어서 오는 아이콘 동작이 다시 열지 않게 하는 데 쓴다.
    private var closedByOutsideClickAt = Date.distantPast
    public var justClosedByOutsideClick: Bool { Date().timeIntervalSince(closedByOutsideClickAt) < 0.4 }

    /// - Parameters:
    ///   - anchorX: 아이콘의 왼쪽 끝(`.leading`) 또는 오른쪽 끝(`.trailing`), Cocoa 화면 x
    ///   - onChange: 열고 닫을 때마다 부른다
    public func show(content: AnyView, anchorX: CGFloat, edge: Edge = .trailing, onChange: @escaping () -> Void) {
        close()
        self.onChange = onChange
        anchor = (anchorX, edge)

        let host = PanelHostingView(rootView: AnyView(content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))))
        host.frame.size = host.fittingSize
        host.onResize = { [weak self] in self?.fitToContent() }

        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: host.frame.size),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        self.panel = panel
        fitToContent()
        panel.makeKeyAndOrderFront(nil)

        // 다른 앱(메뉴바의 다른 아이콘 포함)을 누르면 닫는다
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeFromOutsideClick() }
        } as Any)
        // 우리 앱의 다른 창(다른 메뉴바 아이콘, 설정 창)을 눌러도 닫는다
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel { self.closeFromOutsideClick() }
            }
            return event
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                MainActor.assumeIsolated {
                    if let onEscape = self?.onEscape { onEscape() } else { self?.close() }
                }
                return nil
            }
            return event
        } as Any)
        onChange()
    }

    public func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        onChange?()
    }

    private func closeFromOutsideClick() {
        guard isVisible, !keepOpen else { return }
        closedByOutsideClickAt = Date()
        close()
    }

    /// 내용 크기에 맞춘다(위쪽 끝은 메뉴바 바로 아래에 고정).
    private func fitToContent() {
        guard let panel, let host = panel.contentView else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.x, y: $0.frame.midY)) }) ?? NSScreen.main else { return }
        let size = host.fittingSize
        let menuBarBottom = screen.visibleFrame.maxY
        var x = anchor.edge == .leading ? anchor.x : anchor.x - size.width + 24
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        let frame = NSRect(x: x, y: menuBarBottom - size.height - 6, width: size.width, height: size.height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 내용 크기가 바뀌면 알려 주는 호스팅 뷰(자료를 불러오며 창 높이가 바뀌는 경우).
private final class PanelHostingView: NSHostingView<AnyView> {
    var onResize: (() -> Void)?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        Task { @MainActor [weak self] in self?.onResize?() }
    }
}
