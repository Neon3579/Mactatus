// 메뉴바 서랍 검증: 우리 앱이 만든 상태 아이템(①②③)으로만 실험한다(다른 앱 아이콘은 건드리지 않음).
import AppKit
import ApplicationServices

final class ClickTarget: NSObject {
    @objc func clicked(_ sender: NSStatusBarButton) { log("▶ 상태 아이템 클릭됨: \(sender.title)") }
}
nonisolated(unsafe) let clickTarget = ClickTarget()

final class OverlayView: NSView {
    var drags = 0
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        log("▶ 편집 창이 mouseDown 받음 (⌘=\(e.modifierFlags.contains(.command)))")
    }
    override func mouseDragged(with e: NSEvent) { drags += 1 }
    override func mouseUp(with e: NSEvent) {
        log("▶ 편집 창이 mouseUp 받음 (그 사이 drag \(drags)개)")
        drags = 0
    }
}

@MainActor func makeItem(_ title: String, _ save: String, removable: Bool = false, withMenu: Bool = false) -> NSStatusItem {
    let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    it.autosaveName = save
    it.button?.title = title
    if withMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "SpikeLab 테스트 메뉴", action: nil, keyEquivalent: "")
        it.menu = menu
    } else {
        it.button?.target = clickTarget
        it.button?.action = #selector(ClickTarget.clicked(_:))
    }
    if removable { it.behavior = .removalAllowed }
    return it
}

@MainActor func frameCG(_ it: NSStatusItem) -> CGRect? { it.button?.window.map { toCG($0.frame) } }
func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

@MainActor func describe(_ items: [(String, NSStatusItem)]) -> String {
    items.map { "\($0.0) \(fmt(frameCG($0.1))) visible=\($0.1.isVisible)" }.joined(separator: " | ")
}

@MainActor func order(_ items: [(String, NSStatusItem)]) -> String {
    items.compactMap { name, it in frameCG(it).map { (name, $0.minX) } }
        .sorted { $0.1 < $1.1 }.map(\.0).joined(separator: " < ")
}

func ownAX() async -> [String] {
    await Task.detached { extrasItems(pid: getpid()).map { "\(axLabel($0)) \(fmt(axFrame($0))) \(axActions($0))" } }.value
}

func ownHits() async -> [String] {
    await Task.detached { hitTestMenuBar(step: 2).filter { $0.contains("SpikeLab") } }.value
}

/// 우리 앱의 AX 메뉴바 아이템 중 제목이 title인 것에 AXPress.
func axPress(_ title: String) async -> String {
    await Task.detached { () -> String in
        guard let el = extrasItems(pid: getpid()).first(where: { axLabel($0) == title }) else { return "AX에서 아이템 못 찾음" }
        let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
        return err == .success ? "성공" : "실패(AXError \(err.rawValue))"
    }.value
}

@MainActor func testItems() async {
    let cursor0 = cursorCG()
    let screenW = NSScreen.screens.first?.frame.width ?? 1470
    let div = makeItem("┃", "spike.div")
    let s1 = makeItem("①", "spike.s1")
    let s2 = makeItem("②", "spike.s2", removable: true)
    let s3 = makeItem("③", "spike.s3", withMenu: true)
    let all = [("DIV", div), ("S1", s1), ("S2", s2), ("S3", s3)]
    let spikes = [("S1", s1), ("S2", s2), ("S3", s3)]
    defer {
        for (_, it) in all { NSStatusBar.system.removeStatusItem(it) }
        UserDefaults.standard.removePersistentDomain(forName: "com.mactatus.spikelab")
        CGWarpMouseCursorPosition(cursor0)
        log("정리: 아이템 제거, 설정 삭제, 커서 원위치")
    }
    await wait(1.5)

    // [1] 기본 정보
    log("[1] 생성 직후: \(describe(all))")
    log("[1] 순서(왼→오): \(order(all))")
    log("[1] 상태 아이템 창 번호: \(all.map { "\($0.0)#\($0.1.button?.window?.windowNumber ?? -1)" })")
    let mine = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
    log("[1] CGWindowList의 우리 창: \(mine.map { "#\($0[kCGWindowNumber as String] ?? "?") layer=\($0[kCGWindowLayer as String] ?? "?") onscreen=\($0[kCGWindowIsOnscreen as String] ?? "?")" })")
    await capture(menuBarRect(), name: "items_1_created")
    guard AXIsProcessTrusted() else { log("손쉬운 사용 권한 없음 → 나머지 생략"); return }
    log("[1] AX(우리 앱): \(await ownAX())")
    log("[1] hit test에서 우리 앱: \(await ownHits())")

    // [2] 구분자로 숨기기
    div.length = 10000
    await wait(1.2)
    log("[2] 구분자 폭 10000: \(describe(all))")
    log("[2] AX(우리 앱): \(await ownAX())")
    log("[2] hit test에서 우리 앱: \(await ownHits())")
    await capture(menuBarRect(), name: "items_2_hidden")
    log("[2b] 숨긴 S1에 AXPress → \(await axPress("①"))")
    await wait(0.6)
    div.length = NSStatusItem.variableLength
    await wait(1.2)
    log("[2] 복원: \(describe(all))")

    // [3] 보이는 상태에서 AXPress
    log("[3] 보이는 S1에 AXPress → \(await axPress("①"))")
    await wait(0.6)

    guard CGPreflightPostEventAccess() else { log("이벤트 전송 권한 없음 → 이동·클릭 테스트 생략"); return }

    // [4] ⌘-드래그로 순서 바꾸기
    let sorted = spikes.filter { frameCG($0.1) != nil }.sorted { frameCG($0.1)!.minX < frameCG($1.1)!.minX }
    if let first = sorted.first, let last = sorted.last, let fa = frameCG(first.1), let fb = frameCG(last.1) {
        log("[4] \(first.0)을 \(last.0) 오른쪽으로 ⌘-드래그")
        await synthDrag(from: center(fa), to: CGPoint(x: fb.maxX + 4, y: fa.midY), command: true)
        await wait(1.2)
        log("[4] 결과 순서: \(order(all)) | \(describe(all))")
        await capture(menuBarRect(), name: "items_4_moved")
    }

    // [5] 편집 창(투명 오버레이)으로 클릭·끌기 가로채기
    let union = spikes.compactMap { frameCG($0.1) }.reduce(CGRect.null) { $0.union($1) }
    if !union.isNull {
        let overlayCG = CGRect(x: union.minX - 20, y: 0, width: union.width + 40, height: 33)
        let overlay = NSPanel(contentRect: toCocoa(overlayCG), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        overlay.backgroundColor = NSColor.systemRed.withAlphaComponent(0.3)
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        overlay.contentView = OverlayView()
        overlay.orderFrontRegardless()
        await wait(0.6)
        log("[5] 편집 창 frame=\(fmt(toCG(overlay.frame)))")
        await capture(menuBarRect(), name: "items_5_overlay")
        if let f = frameCG(s1) {
            await synthClick(at: center(f))
            await wait(0.6)
            let before = order(all)
            if let g = frameCG(s3) {
                await synthDrag(from: center(f), to: CGPoint(x: max(g.maxX, f.maxX) + 4, y: f.midY), command: true)
            }
            await wait(1.0)
            log("[5] 편집 창 위에서 클릭·⌘-드래그: 순서 전 \(before) → 후 \(order(all))")
        }
        overlay.orderOut(nil)
    }

    // [6] 메뉴가 있는 아이템(S3)에 AXPress → 메뉴가 어디 뜨는지 (보이는 상태 / 숨긴 상태)
    for hidden in [false, true] {
        if hidden { div.length = 10000; await wait(1.2) }
        let tag = hidden ? "hidden" : "visible"
        let watcher = Task.detached {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            await capture(CGRect(x: 0, y: 0, width: screenW, height: 260), name: "items_6_menu_\(tag)")
            postKey(0x35) // Esc
        }
        log("[6] \(tag) 상태 S3(메뉴)에 AXPress → \(await axPress("③"))")
        _ = await watcher.value
        await wait(0.6)
        if hidden { div.length = NSStatusItem.variableLength; await wait(1.2) }
    }

    // [7] 메뉴바 밖(서랍 쪽)에 놓기: 기본 아이템 vs removalAllowed 아이템
    for (name, it) in [("S3(기본)", s3), ("S2(removalAllowed)", s2)] {
        guard let f = frameCG(it) else { continue }
        await synthDrag(from: center(f), to: CGPoint(x: f.midX, y: 300), command: true)
        await wait(1.5)
        log("[7] \(name)을 메뉴바 밖에 놓은 뒤: visible=\(it.isVisible) frame=\(fmt(frameCG(it)))")
    }
    await capture(menuBarRect(), name: "items_7_dropout")
}
