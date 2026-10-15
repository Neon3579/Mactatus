import AppKit

/// 끄는 동안 커서를 따라다니는 아이콘(메뉴바·서랍 패널 위를 넘나들어야 해서 따로 띄운다).
@MainActor
final class DragGhost {
    private var window: NSPanel?

    func show(image: NSImage?) {
        guard window == nil else { return }
        let size = NSSize(width: 28, height: 28)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = image ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        view.alphaValue = 0.85
        panel.contentView = view
        panel.orderFrontRegardless()
        window = panel
    }

    /// Cocoa 화면 좌표로 옮긴다(커서가 아이콘 가운데에 오게).
    func move(to point: NSPoint) {
        window?.setFrameOrigin(NSPoint(x: point.x - 14, y: point.y - 14))
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// 편집 모드: 메뉴바 오른쪽(상태 아이콘 영역) 위에 덮는 투명한 창.
/// ⌘ 없이 아이콘을 끌어 순서를 바꾸거나, 아래 서랍 패널로 끌어 넣을 수 있다.
/// 실제로 옮길 때는 덮개를 잠깐 치우고 ⌘-끌기를 합성한다(덮개 창이 클릭을 가로챈다는 것은 0단계에서 확인).
@MainActor
final class EditOverlayHost {
    private var panel: NSPanel?
    private weak var view: EditOverlayView?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(controller: DrawerController) {
        close()
        guard let screen = NSScreen.screens.first else { return }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let left = controller.statusAreaLeft
        let frame = NSRect(x: left, y: screen.frame.maxY - menuBarHeight, width: screen.frame.maxX - left, height: menuBarHeight)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = EditOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        view.controller = controller
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        self.view = view
    }

    /// 실제 아이콘을 옮기는 동안 잠깐 치운다(합성한 ⌘-끌기가 메뉴바에 닿도록).
    func suspend() { panel?.orderOut(nil) }

    func resume(controller: DrawerController) {
        guard panel != nil else { return }
        show(controller: controller)
    }

    func redraw() { view?.needsDisplay = true }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

final class EditOverlayView: NSView {
    weak var controller: DrawerController?
    /// 끄는 중인 대상(아이콘 key, ⌄면 nil)과 시작 위치
    private var dragging: (item: MenuBarItem?, start: NSPoint)?
    /// 메뉴바 위에서 놓일 자리(CG x)
    private var insertionX: CGFloat?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 화면 CG x → 이 뷰의 x
    private func localX(_ x: CGFloat) -> CGFloat { x - (window?.frame.minX ?? 0) }

    @MainActor
    private var targets: [(item: MenuBarItem?, frame: CGRect)] {
        guard let controller, let scan = controller.scan else { return [] }
        var list: [(MenuBarItem?, CGRect)] = scan.items
            .filter { !$0.isHidden && !$0.isSystem }
            .map { ($0, $0.frame) }
        if let toggle = scan.toggle, !scan.toggleHidden { list.append((nil, toggle)) }
        return list.sorted { $0.1.minX < $1.1.minX }
    }

    override func draw(_ dirtyRect: NSRect) {
        MainActor.assumeIsolated {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            bounds.fill()
            for (item, frame) in targets {
                let rect = NSRect(x: localX(frame.minX) + 1, y: 3, width: frame.width - 2, height: bounds.height - 6)
                let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
                (item == nil ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.55)).setStroke()
                path.lineWidth = item == nil ? 2 : 1
                if item != nil { path.setLineDash([3, 2], count: 2, phase: 0) }
                path.stroke()
            }
            if let insertionX {
                NSColor.controlAccentColor.setFill()
                NSRect(x: localX(insertionX) - 1, y: 2, width: 2, height: bounds.height - 4).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            let x = (window?.frame.minX ?? 0) + convert(event.locationInWindow, from: nil).x
            guard let hit = targets.first(where: { $0.frame.minX <= x && x <= $0.frame.maxX }) else { return }
            dragging = (hit.item, NSEvent.mouseLocation)
            controller?.beginGhost(for: hit.item)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        MainActor.assumeIsolated {
            guard dragging != nil, let controller else { return }
            let point = NSEvent.mouseLocation
            controller.moveGhost(to: point)
            insertionX = controller.isOverMenuBar(point) ? nearestGap(to: point.x) : nil
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            guard let drag = dragging, let controller else { return }
            dragging = nil
            insertionX = nil
            needsDisplay = true
            let point = NSEvent.mouseLocation
            controller.endGhost()
            guard hypot(point.x - drag.start.x, point.y - drag.start.y) > 4 else { return }
            if controller.isOverPanel(point), let item = drag.item {
                Task { await controller.putInDrawer(item) }
            } else if controller.isOverMenuBar(point) {
                let x = nearestGap(to: point.x)
                Task { await controller.move(drag.item, toX: x) }
            }
        }
    }

    /// 아이콘 사이 틈 중 가장 가까운 곳(CG x).
    @MainActor
    private func nearestGap(to x: CGFloat) -> CGFloat {
        let frames = targets.map(\.frame)
        guard !frames.isEmpty else { return x }
        var gaps = [frames[0].minX + 1]
        for (a, b) in zip(frames, frames.dropFirst()) { gaps.append((a.maxX + b.minX) / 2) }
        gaps.append(frames[frames.count - 1].maxX - 1)
        return gaps.min { abs($0 - x) < abs($1 - x) } ?? x
    }
}
