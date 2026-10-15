// macOS 27 기본 "가려진 메뉴 막대 항목 보기"(«) 버튼과, 숨겨진 다른 앱 아이콘 AXPress 검증.
// 다른 앱 메뉴는 열었다가 바로 Esc로 닫는다.
import AppKit
import ApplicationServices

func allAttributes(_ el: AXUIElement) -> [String: String] {
    var names: CFArray?
    AXUIElementCopyAttributeNames(el, &names)
    var out: [String: String] = [:]
    for n in names as? [String] ?? [] {
        guard let v = axValue(el, n) else { continue }
        if CFGetTypeID(v) == AXUIElementGetTypeID() { out[n] = "<element>"; continue }
        if let arr = v as? [Any] { out[n] = "[\(arr.count)개]"; continue }
        out[n] = "\(v)".replacingOccurrences(of: "\n", with: " ").prefix(80).description
    }
    return out
}

func menuBarAgentPid() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier
}

/// 다른 앱의 AX 요소를 누르고, 1.2초 뒤 화면 위쪽을 캡처한 뒤 Esc.
func pressAndCapture(_ el: AXUIElement, name: String, height: CGFloat = 420) async -> String {
    let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
    try? await Task.sleep(nanoseconds: 1_200_000_000)
    await capture(CGRect(x: 0, y: 0, width: NSScreen.screens.first?.frame.width ?? 1470, height: height), name: name)
    var windows: [String] = []
    if let pid = menuBarAgentPid() {
        let app = AXUIElementCreateApplication(pid)
        windows = (axValue(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).map { "\(axString($0, kAXRoleAttribute) ?? "?") \(fmt(axFrame($0)))" }
    }
    postKey(0x35) // Esc
    try? await Task.sleep(nanoseconds: 600_000_000)
    return "AXPress=\(err == .success ? "성공" : "AXError \(err.rawValue)") | MenuBarAgent 창: \(windows)"
}

/// 지정한 앱(번들 ID)의 메뉴바 아이콘 위치를 보고, 눌러서 열린 창을 캡처한다. Mactatus 확인용.
@MainActor func testPressApp(_ bundleID: String) async {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        log("\(bundleID) 실행 중 아님"); return
    }
    let lines = await Task.detached { () -> [String] in
        let items = extrasItems(pid: app.processIdentifier)
        var out = ["메뉴바 아이템 \(items.count)개: \(items.map { "\(axLabel($0)) \(fmt(axFrame($0)))" })"]
        if let item = items.first {
            let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
            out.append("AXPress → \(err == .success ? "성공" : "AXError \(err.rawValue)")")
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            let w = NSScreen.screens.first?.frame.width ?? 1470
            await capture(CGRect(x: w - 760, y: 0, width: 760, height: 760), name: "press_\(bundleID)")
            await capture(CGRect(x: 0, y: 0, width: w, height: 760), name: "press_\(bundleID)_full")
            postKey(0x35) // Esc로 닫기
            try? await Task.sleep(nanoseconds: 500_000_000)
            out.append("Esc 보냄")
        }
        return out
    }.value
    lines.forEach(log)
}

@MainActor func testNative() async {
    let lines = await Task.detached { () -> [String] in
        var out: [String] = []
        guard let pid = menuBarAgentPid() else { return ["MenuBarAgent 없음"] }
        let items = extrasItems(pid: pid)
        guard let chevron = items.first(where: { axLabel($0).contains("가려진") || (axString($0, kAXIdentifierAttribute) ?? "").lowercased().contains("hidden") }) else {
            return ["« 버튼 못 찾음: \(items.map(axLabel))"]
        }
        out.append("[1] « 버튼 속성: \(allAttributes(chevron))")
        out.append("[1] « 누름 → \(await pressAndCapture(chevron, name: "native_1_chevron"))")

        // 숨겨진(겹쳐 있는) 다른 앱 아이콘 찾기: 프레임이 « 근처에 겹친 것
        let cf = axFrame(chevron) ?? .zero
        var hidden: [(String, AXUIElement)] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != pid {
            for el in extrasItems(pid: app.processIdentifier) {
                if let f = axFrame(el), f.maxX <= cf.maxX + 2, f.maxX >= cf.minX - 60 {
                    hidden.append((app.localizedName ?? "?", el))
                }
            }
        }
        out.append("[2] « 근처(숨겨진 것으로 보이는) 아이템: \(hidden.map { "\($0.0) \(fmt(axFrame($0.1)))" })")
        if let target = hidden.first(where: { $0.0 == "Notion" }) ?? hidden.first {
            out.append("[2] 숨겨진 \(target.0) 아이콘 속성: \(allAttributes(target.1))")
            out.append("[2] 숨겨진 \(target.0) 아이콘 누름 → \(await pressAndCapture(target.1, name: "native_2_hidden_press"))")
        }
        return out
    }.value
    lines.forEach(log)
}


/// 개발 확인용: 화면 좌표(x,y)를 한 번 클릭하고 위쪽 화면을 캡처한 뒤 Esc.
@MainActor func testClickAt(_ arg: String) async {
    let parts = arg.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else { log("인자 형식: x,y"); return }
    let cursor0 = cursorCG()
    await synthClick(at: CGPoint(x: parts[0], y: parts[1]))
    await wait(1.5)
    await capture(CGRect(x: 0, y: 0, width: NSScreen.screens.first?.frame.width ?? 1470, height: 620), name: "clickat")
    postKey(0x35)
    await wait(0.4)
    CGWarpMouseCursorPosition(cursor0)
    log("클릭·캡처 완료")
}

/// 개발 확인용: 화면 영역(x,y,w,h)만 캡처한다(클릭 없음).
@MainActor func testCaptureRegion(_ arg: String) async {
    let p = arg.split(separator: ",").compactMap { Double($0) }
    guard p.count == 4 else { log("인자 형식: x,y,w,h"); return }
    await capture(CGRect(x: p[0], y: p[1], width: p[2], height: p[3]), name: "region")
}

