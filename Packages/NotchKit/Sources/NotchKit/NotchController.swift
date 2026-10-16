import AppKit
import Observation
import SwiftUI

/// 노치 허브: 내장 디스플레이의 노치 둘레에 검은 모양을 띄우고, 모듈 내용을 미니·펼침 상태로 보여준다.
///
/// - 창은 가장 큰 모양(펼침) 크기로 고정하고 안에서 모양만 바꾼다. 모양 밖은 투명하고, 마우스가 모양 위에 있을 때만
///   이벤트를 받는다(그 밖의 클릭은 아래 메뉴바로 그대로 간다).
/// - 전체 화면 Space로 바뀌면 시스템이 창을 화면 아래로 옮기므로 Space가 바뀔 때마다 위치를 다시 맞춘다(0단계 5번).
/// - 노치가 없는 화면만 있을 때(덮개를 닫고 외장 모니터만 쓸 때)는 쉰다. 외장 모니터에 가상 노치는 띄우지 않는다.
@MainActor
@Observable
public final class NotchController {
    public enum State: Sendable { case idle, compact, expanded }

    public private(set) var geometry: NotchGeometry?
    public private(set) var isExpanded = false
    /// 펼친 화면에서 고른 탭(없으면 미니로 보이던 모듈)
    public var selectedModuleID: String?
    public var modules: [NotchModule] = []
    /// 펼친 화면의 톱니바퀴 버튼
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    /// 마우스를 올려 두면 펼치기까지 기다리는 시간
    @ObservationIgnored public var hoverDelay: Duration = .milliseconds(150)

    /// 미니 상태에서 노치 양옆으로 나오는 폭
    static let wing: CGFloat = 36
    static let expandedSize = CGSize(width: 500, height: 178)
    static let topRadius: CGFloat = 6
    /// 창 가장자리 여유(그림자)
    static let margin: CGFloat = 24

    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var mouseInside = false
    @ObservationIgnored private var trackTask: Task<Void, Never>?

    public init() {}

    public var state: State {
        if isExpanded { return .expanded }
        return compactModule != nil ? .compact : .idle
    }

    /// 미니 상태로 보여줄 모듈: 보여줄 것이 있는 모듈 중 우선순위가 가장 높은 것
    public var compactModule: NotchModule? {
        modules.filter { $0.compactPriority != nil }.max { ($0.compactPriority ?? 0) < ($1.compactPriority ?? 0) }
    }

    public var selectedModule: NotchModule? {
        modules.first { $0.id == selectedModuleID }
            ?? compactModule.flatMap { $0.showsTab ? $0 : nil }
            ?? modules.first { $0.showsTab }
    }

    /// 지금 상태의 모양 크기(위쪽 양 끝의 휘어짐 포함)
    var shapeSize: CGSize { size(for: state) }

    func size(for state: State) -> CGSize {
        guard let geometry else { return .zero }
        let notch = geometry.notch.size
        switch state {
        case .idle: return CGSize(width: notch.width + Self.topRadius * 2, height: notch.height)
        case .compact:
            let wing = compactModule?.compactWingWidth ?? Self.wing
            return CGSize(width: notch.width + (wing + Self.topRadius) * 2, height: notch.height)
        case .expanded: return CGSize(width: max(Self.expandedSize.width, notch.width + 200), height: Self.expandedSize.height)
        }
    }

    // MARK: - 켜기·끄기

    public func start() {
        guard panel == nil else { return }
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        let host = NSHostingView(rootView: NotchRootView(controller: self))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        reposition()
        observe()
    }

    public func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers.removeAll()
        panel?.orderOut(nil)
        panel = nil
        isExpanded = false
    }

    // MARK: - 열고 닫기

    public func expand() {
        guard !isExpanded, geometry != nil else { return }
        collapseTask?.cancel()
        isExpanded = true
        panel?.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    public func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        selectedModuleID = nil
        updateMouse()
    }

    public func select(_ module: NotchModule) {
        selectedModuleID = module.id
    }

    /// 스냅샷 확인용: 창 없이 정해진 노치 위치(기본값은 MacBook Air M2)와 상태로 그린 화면.
    public func previewView(expanded: Bool,
                            notch: CGRect = CGRect(x: 645.5, y: 924, width: 179, height: 32),
                            screen: CGRect = CGRect(x: 0, y: 0, width: 1470, height: 956)) -> some View {
        let geometry = NotchGeometry(notch: notch, screen: screen)
        self.geometry = geometry
        isExpanded = expanded
        let size = geometry.panelFrame(largest: size(for: .expanded), margin: Self.margin).size
        return NotchRootView(controller: self).frame(width: size.width, height: size.height)
    }

    // MARK: - 위치

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }),
              let geometry = NotchGeometry.make(screen: screen.frame, topLeft: screen.auxiliaryTopLeftArea,
                                                topRight: screen.auxiliaryTopRightArea) else {
            self.geometry = nil
            isExpanded = false
            panel.orderOut(nil)
            return
        }
        self.geometry = geometry
        let largest = size(for: .expanded)
        let frame = geometry.panelFrame(largest: largest, margin: Self.margin)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        // 전체 화면 Space로 바뀌면 시스템이 창을 아래로 옮긴다 → 바로, 그리고 전환 애니메이션 뒤에 한 번 더 맞춘다
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.reposition()
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        // 마우스 위치로 펼치기·접기와 클릭 통과를 정한다(다른 앱 위에서는 전역, 우리 창 위에서는 지역 감시)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouse() }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouse() }
            return event
        } as Any)
        // 펼친 채로 다른 곳을 누르면 접는다
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isExpanded else { return }
                self.collapse()
            }
        } as Any)
    }

    // MARK: - 마우스

    private func updateMouse() {
        guard let geometry, let panel else { return }
        let point = NSEvent.mouseLocation
        let inside = geometry.shapeFrame(shapeSize).contains(point)
        panel.ignoresMouseEvents = !inside
        guard inside != mouseInside else { return }
        mouseInside = inside
        if inside {
            startTracking()
            collapseTask?.cancel()
            guard !isExpanded else { return }
            let delay = hoverDelay
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.mouseInside else { return }
                self.expand()
            }
        } else {
            hoverTask?.cancel()
            guard isExpanded else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, !self.mouseInside else { return }
                self.collapse()
            }
        }
    }

    /// 마우스가 모양 위에 있거나 펼쳐져 있는 동안 위치를 직접 확인한다.
    /// 노치 창은 키 창이 되지 않아서, 창 안(모양 밖의 투명한 곳, 예: 노치 옆 메뉴바 아이콘 위)에서 움직이면
    /// 이동 알림이 오지 않는다. 그러면 클릭 통과로 돌아가지 못해 그 아래 메뉴바 아이콘(서랍 ⌄ 등)을 누를 수 없었다.
    private func startTracking() {
        guard trackTask == nil else { return }
        trackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                self.updateMouse()
                if !self.mouseInside && !self.isExpanded { break }
            }
            self?.trackTask = nil
        }
    }
}

/// 전체 화면 Space로 바뀔 때 시스템이 창을 화면 안쪽으로 옮기지 못하게 막는다.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    /// 키 창이 되지 않는다: 펼쳐도 앞 앱의 키보드 입력을 가로채지 않게
    override var canBecomeKey: Bool { false }
}
