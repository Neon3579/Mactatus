// 노치 패널 검증: 노치 주변 검은 알약 창이 데스크톱·전체 화면에서 보이는지, 마우스 올림을 받는지.
import AppKit

/// 전체 화면 Space로 바뀔 때 시스템이 창을 화면 안쪽으로 옮기지 못하게 막는다.
final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { log("▶ 노치: 마우스 들어옴"); onHover?(true) }
    override func mouseExited(with event: NSEvent) { log("▶ 노치: 마우스 나감"); onHover?(false) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
        ("Mactatus" as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 23), withAttributes: attrs)
        ("♪" as NSString).draw(at: NSPoint(x: bounds.width - 26, y: bounds.height - 23), withAttributes: attrs)
    }
}

@MainActor func testNotch(extraSeconds: Double) async {
    guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }),
          let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea else {
        log("노치 있는 화면 없음"); return
    }
    let cursor0 = cursorCG()
    let notch = NSRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: l.height)
    let compact = notch.insetBy(dx: -80, dy: 0)
    let expanded = NSRect(x: notch.midX - 200, y: screen.frame.maxY - 120, width: 400, height: 120)
    let topStrip = CGRect(x: 0, y: 0, width: screen.frame.width, height: 140)

    let panel = NotchPanel(contentRect: compact, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    let view = NotchView(frame: NSRect(origin: .zero, size: compact.size))
    view.autoresizingMask = [.width, .height]
    panel.contentView = view
    view.onHover = { inside in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().setFrame(inside ? expanded : compact, display: true)
        }
    }
    panel.orderFrontRegardless()
    await wait(1)
    log("[1] 데스크톱: 노치=\(fmt(toCG(notch))) 패널=\(fmt(toCG(panel.frame))) 보임=\(panel.occlusionState.contains(.visible)) 현재Space=\(panel.isOnActiveSpace)")
    await capture(topStrip, name: "notch_1_desktop")

    // [2] 우리 창을 전체 화면으로 → 새 Space에서도 패널이 보이는지
    NSApp.setActivationPolicy(.regular)
    let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 450),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    win.title = "SpikeLab 전체 화면 테스트"
    win.collectionBehavior = [.fullScreenPrimary]
    win.backgroundColor = .systemTeal
    win.makeKeyAndOrderFront(nil)
    NSApp.activate()
    await wait(1)
    win.toggleFullScreen(nil)
    await wait(3.5)
    log("[2] 전체 화면: 창 fullScreen=\(win.styleMask.contains(.fullScreen)) | 패널=\(fmt(toCG(panel.frame))) 보임=\(panel.occlusionState.contains(.visible)) 현재Space=\(panel.isOnActiveSpace)")
    log("[2] 전체 화면일 때 화면: frame=\(screen.frame) visible=\(screen.visibleFrame) safeTop=\(screen.safeAreaInsets.top) | 패널 Cocoa frame=\(panel.frame) | 창 frame=\(win.frame)")
    await capture(CGRect(x: 0, y: 0, width: screen.frame.width, height: 956), name: "notch_2_fullscreen_full")
    panel.setFrame(compact, display: true)
    await wait(0.5)
    log("[2b] 패널을 다시 위로 → Cocoa frame=\(panel.frame) 보임=\(panel.occlusionState.contains(.visible))")
    await capture(topStrip, name: "notch_2_fullscreen")

    // [3] 전체 화면에서 마우스 올림 → 펼침
    if CGPreflightPostEventAccess() {
        let c = toCG(compact)
        post(.mouseMoved, CGPoint(x: c.minX + 30, y: 8))
        await wait(1.0)
        log("[3] 마우스 올림 후 패널=\(fmt(toCG(panel.frame)))")
        await capture(topStrip, name: "notch_3_hover_fullscreen")
        post(.mouseMoved, CGPoint(x: c.midX, y: 500))
        await wait(0.8)
        log("[3] 마우스 뺀 후 패널=\(fmt(toCG(panel.frame)))")
    } else {
        log("[3] 이벤트 전송 권한 없음 → 마우스 올림 테스트 생략")
    }
    win.toggleFullScreen(nil)
    await wait(2.5)
    win.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
    CGWarpMouseCursorPosition(cursor0)

    // [5] 편집 모드용 창이 메뉴바 위에 보이는 창 레벨 찾기 (클릭은 통과시킴)
    let stripCG = CGRect(x: toCG(notch).maxX + 20, y: 0, width: 220, height: 33)
    let levels: [(String, Int)] = [
        ("statusBar+1", NSWindow.Level.statusBar.rawValue + 1),
        ("mainMenu+3", NSWindow.Level.mainMenu.rawValue + 3),
        ("popUpMenu", NSWindow.Level.popUpMenu.rawValue),
        ("screenSaver", NSWindow.Level.screenSaver.rawValue),
    ]
    for (name, level) in levels {
        let strip = NSPanel(contentRect: toCocoa(stripCG), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        strip.level = NSWindow.Level(rawValue: level)
        strip.backgroundColor = NSColor.systemRed.withAlphaComponent(0.45)
        strip.isOpaque = false
        strip.hasShadow = false
        strip.ignoresMouseEvents = true
        strip.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        strip.orderFrontRegardless()
        await wait(0.6)
        log("[5] 빨간 띠 레벨 \(name)(\(level)) frame=\(fmt(toCG(strip.frame)))")
        await capture(menuBarRect(), name: "notch_5_strip_\(name)")
        strip.orderOut(nil)
    }

    // [4] 관찰: 사용자가 다른 앱을 전체 화면으로 바꿔 볼 수 있음
    log("[4] \(Int(extraSeconds))초 관찰")
    var t = 0.0
    while t < extraSeconds {
        log("   앞 앱=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") 패널 보임=\(panel.occlusionState.contains(.visible)) 현재Space=\(panel.isOnActiveSpace)")
        await wait(2)
        t += 2
    }
}
