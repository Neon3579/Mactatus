import AppKit
import ApplicationServices
import ScreenCaptureKit

// MARK: - 로그

enum Log {
    nonisolated(unsafe) static var handle: FileHandle?
    static let start = Date()

    static func open(_ path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }
}

func log(_ s: String) {
    let line = String(format: "[%5.2f] ", Date().timeIntervalSince(Log.start)) + s + "\n"
    Log.handle?.write(line.data(using: .utf8)!)
}

nonisolated(unsafe) var outDir = ""

@MainActor func wait(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - 좌표 (Cocoa: 왼쪽 아래 원점 ↔ CG: 왼쪽 위 원점)

func primaryHeight() -> CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
func toCG(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight() - r.maxY, width: r.width, height: r.height) }
func toCocoa(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryHeight() - r.maxY, width: r.width, height: r.height) }
func fmt(_ r: CGRect?) -> String {
    guard let r else { return "nil" }
    return String(format: "(x %.0f, y %.0f, w %.0f, h %.0f)", r.minX, r.minY, r.width, r.height)
}
func cursorCG() -> CGPoint {
    let p = NSEvent.mouseLocation
    return CGPoint(x: p.x, y: primaryHeight() - p.y)
}

// MARK: - 손쉬운 사용(AX)

func axValue(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { axValue(el, attr) as? String }
func axChildren(_ el: AXUIElement) -> [AXUIElement] { axValue(el, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p = axValue(el, kAXPositionAttribute), let s = axValue(el, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt)
    AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}
func axActions(_ el: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(el, &names)
    return names as? [String] ?? []
}
func axLabel(_ el: AXUIElement) -> String {
    axString(el, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 }
        ?? axString(el, kAXDescriptionAttribute).flatMap { $0.isEmpty ? nil : $0 }
        ?? axString(el, kAXIdentifierAttribute) ?? "-"
}

/// 앱의 메뉴바 추가 아이템(AXExtrasMenuBar 자식). 자기 자신을 조회할 땐 메인 스레드가 아닌 곳에서 부를 것.
func extrasItems(pid: pid_t) -> [AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    guard let bar = axValue(app, "AXExtrasMenuBar") else { return [] }
    return axChildren(bar as! AXUIElement)
}

/// 메뉴바 높이에서 x를 훑으며 어떤 프로세스·요소가 그려져 있는지 기록한다.
func hitTestMenuBar(y: CGFloat = 12, step: CGFloat = 4) -> [String] {
    let sys = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(sys, 0.5)
    var out: [String] = []
    var last = ""
    let width = NSScreen.screens.first?.frame.width ?? 0
    var x: CGFloat = 0
    while x < width {
        var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(sys, Float(x), Float(y), &el) == .success, let el {
            var pid: pid_t = 0
            AXUIElementGetPid(el, &pid)
            let who = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
            let key = "\(who) | \(axString(el, kAXRoleAttribute) ?? "?") | \(axLabel(el))"
            if key != last {
                out.append("x=\(Int(x)) → \(key)")
                last = key
            }
        }
        x += step
    }
    return out
}

// MARK: - 이벤트 합성

func post(_ type: CGEventType, _ p: CGPoint, flags: CGEventFlags = [], clickState: Int64 = 1) {
    let src = CGEventSource(stateID: .hidSystemState)
    guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: clickState)
    e.post(tap: .cghidEventTap)
}

func postCommandKey(down: Bool) {
    let src = CGEventSource(stateID: .hidSystemState)
    let e = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: down)
    e?.flags = down ? .maskCommand : []
    e?.post(tap: .cghidEventTap)
}

func postKey(_ code: CGKeyCode) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
}

@MainActor func synthDrag(from a: CGPoint, to b: CGPoint, command: Bool, steps: Int = 15) async {
    let flags: CGEventFlags = command ? .maskCommand : []
    if command { postCommandKey(down: true); await wait(0.05) }
    post(.mouseMoved, a, flags: flags)
    await wait(0.08)
    post(.leftMouseDown, a, flags: flags)
    await wait(0.25)
    for i in 1...steps {
        let t = CGFloat(i) / CGFloat(steps)
        post(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), flags: flags)
        await wait(0.03)
    }
    await wait(0.15)
    post(.leftMouseUp, b, flags: flags)
    if command { await wait(0.05); postCommandKey(down: false) }
}

@MainActor func synthClick(at p: CGPoint) async {
    post(.mouseMoved, p)
    await wait(0.08)
    post(.leftMouseDown, p)
    await wait(0.06)
    post(.leftMouseUp, p)
}

// MARK: - 화면 캡처 (ScreenCaptureKit)

/// 주 화면의 일부(CG 좌표, 포인트 단위)를 PNG로 저장한다.
func capture(_ rect: CGRect, name: String) async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            log("캡처 실패: 주 화면 없음"); return
        }
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = rect
        cfg.width = Int(rect.width * 2)
        cfg.height = Int(rect.height * 2)
        cfg.showsCursor = false
        let img = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg)
        let path = "\(outDir)/\(name).png"
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        log("캡처 저장: \(name).png")
    } catch {
        log("캡처 실패(\(name)): \(error.localizedDescription)")
    }
}

func menuBarRect() -> CGRect {
    CGRect(x: 0, y: 0, width: NSScreen.screens.first?.frame.width ?? 0, height: 34)
}
