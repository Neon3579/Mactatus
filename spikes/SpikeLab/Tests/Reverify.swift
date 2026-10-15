// 3단계 재검증: 저장 위치로 아이콘 놓기, 구분자로 숨기기(« 와의 관계), ⌘-끌기, 메뉴바 밖에 놓기.
// 테스트 아이콘(┃①②)만 옮긴다. 구분자를 넓히는 2초 동안 왼쪽의 실제 아이콘이 잠깐 밀려날 수 있다.
import AppKit
import ApplicationServices

/// hit test로 본 우리 아이콘의 화면 x 위치(라벨 → x).
func ownScreenPositions() async -> [String: Int] {
    let hits = await Task.detached { hitTestMenuBar(step: 2) }.value
    var result: [String: Int] = [:]
    for line in hits where line.contains("SpikeLab") {
        // "x=1234 → SpikeLab | AXMenuBarItem | ①"
        guard let x = line.split(separator: " ").first.flatMap({ Int($0.dropFirst(2)) }),
              let label = line.split(separator: "|").last?.trimmingCharacters(in: .whitespaces) else { continue }
        if result[label] == nil { result[label] = x }
    }
    return result
}

/// 모든 앱의 메뉴바 아이콘 위치 요약(밀려났는지 보려고).
func allExtrasSummary() async -> String {
    await Task.detached { () -> String in
        NSWorkspace.shared.runningApplications.flatMap { app -> [String] in
            extrasItems(pid: app.processIdentifier).map { el in
                let x = axFrame(el).map { Int($0.minX) } ?? -9999
                return "\(app.localizedName ?? "?"):\(axLabel(el).prefix(12))@\(x)"
            }
        }.sorted().joined(separator: ", ")
    }.value
}

@MainActor func testReverify() async {
    let cursor0 = cursorCG()
    let defaults = UserDefaults.standard
    // 위치값: 오른쪽 끝에서 떨어진 거리로 알려져 있음(클수록 왼쪽)
    let positions: [String: Double] = ["spike.div": 330, "spike.s2": 360, "spike.s1": 390]
    for (name, value) in positions { defaults.set(value, forKey: "NSStatusItem Preferred Position \(name)") }
    defaults.synchronize()

    let div = makeItem("┃", "spike.div")
    let s1 = makeItem("①", "spike.s1")
    let s2 = makeItem("②", "spike.s2", removable: true)
    defer {
        for it in [div, s1, s2] { NSStatusBar.system.removeStatusItem(it) }
        UserDefaults.standard.removePersistentDomain(forName: "com.mactatus.spikelab")
        CGWarpMouseCursorPosition(cursor0)
        log("정리: 테스트 아이콘 제거, 설정 삭제, 커서 원위치")
    }
    await wait(1.5)

    // [A] 저장 위치로 보이는 자리에 놓였는지
    let a = await ownScreenPositions()
    log("[A] 화면에서 찾은 테스트 아이콘 위치: \(a)")
    log("[A] 우리 앱 AX: \(await ownAX())")
    await capture(menuBarRect(), name: "reverify_A_placed")
    log("[A] 전체 아이콘(전): \(await allExtrasSummary())")

    // [B] 구분자 넓히기 → 왼쪽 아이콘이 화면 밖으로? « 안으로?
    div.length = 2000
    await wait(1.0)
    log("[B] 구분자 2000 — 우리 아이콘: \(await ownScreenPositions())")
    log("[B] 전체 아이콘(넓힌 뒤): \(await allExtrasSummary())")
    await capture(menuBarRect(), name: "reverify_B_divider_wide")
    div.length = NSStatusItem.variableLength
    await wait(1.2)
    log("[B] 복원 — 우리 아이콘: \(await ownScreenPositions())")
    await capture(menuBarRect(), name: "reverify_B_restored")

    // [C] ⌘-끌기로 ①을 ② 오른쪽으로(둘 다 보일 때만)
    let c0 = await ownScreenPositions()
    if let x1 = c0["①"], let x2 = c0["②"] {
        let y: CGFloat = 15
        let target = CGFloat(max(x1, x2) + 30)
        log("[C] ① x=\(x1) → \(Int(target))로 ⌘-끌기")
        await synthDrag(from: CGPoint(x: CGFloat(x1) + 8, y: y), to: CGPoint(x: target, y: y), command: true)
        await wait(1.2)
        log("[C] 끌기 후 위치: \(await ownScreenPositions())")
        log("[C] 저장된 위치값: ① \(defaults.double(forKey: "NSStatusItem Preferred Position spike.s1")), ② \(defaults.double(forKey: "NSStatusItem Preferred Position spike.s2"))")
        await capture(menuBarRect(), name: "reverify_C_dragged")
    } else {
        log("[C] ①·②가 화면에 보이지 않아 ⌘-끌기 생략")
    }

    // [D] 메뉴바 밖에 놓기: ①(기본) / ②(removalAllowed)
    for (label, item) in [("①", s1), ("②", s2)] {
        guard let x = await ownScreenPositions()[label] else { log("[D] \(label) 안 보임 → 생략"); continue }
        await synthDrag(from: CGPoint(x: CGFloat(x) + 8, y: 15), to: CGPoint(x: CGFloat(x) + 8, y: 320), command: true)
        await wait(1.5)
        log("[D] \(label)을 메뉴바 밖에 놓은 뒤: isVisible=\(item.isVisible) 위치=\(await ownScreenPositions()[label].map(String.init) ?? "화면에 없음")")
    }
    await capture(menuBarRect(), name: "reverify_D_dropped")
}

/// 2차: 보이는 테스트 아이콘끼리 ⌘-끌기, 구분자를 조금씩 넓힐 때 무엇이 « 로 가는지.
@MainActor func testReverify2() async {
    let cursor0 = cursorCG()
    let defaults = UserDefaults.standard
    let positions: [String: Double] = ["spike.div": 300, "spike.s2": 312, "spike.s1": 324]
    for (name, value) in positions { defaults.set(value, forKey: "NSStatusItem Preferred Position \(name)") }
    let div = makeItem("┃", "spike.div")
    let s1 = makeItem("①", "spike.s1")
    let s2 = makeItem("②", "spike.s2")
    defer {
        for it in [div, s1, s2] { NSStatusBar.system.removeStatusItem(it) }
        UserDefaults.standard.removePersistentDomain(forName: "com.mactatus.spikelab")
        CGWarpMouseCursorPosition(cursor0)
        log("정리 완료")
    }
    await wait(1.5)
    log("[A] 위치: \(await ownScreenPositions())")
    await capture(menuBarRect(), name: "reverify2_A")

    // [C] ⌘-끌기
    let p = await ownScreenPositions()
    if let x1 = p["①"], let x2 = p["②"] {
        let target = CGFloat(max(x1, x2) + 26)
        await synthDrag(from: CGPoint(x: CGFloat(x1) + 8, y: 15), to: CGPoint(x: target, y: 15), command: true)
        await wait(1.2)
        log("[C] ①을 ② 오른쪽으로 ⌘-끌기 후: \(await ownScreenPositions()) | 저장값 ① \(defaults.double(forKey: "NSStatusItem Preferred Position spike.s1")) ② \(defaults.double(forKey: "NSStatusItem Preferred Position spike.s2"))")
        await capture(menuBarRect(), name: "reverify2_C")
    } else {
        log("[C] ①·② 중 보이지 않는 것이 있어 생략: \(p)")
    }

    // [E] 구분자를 조금씩 넓히기
    for width in [60.0, 150, 300] {
        div.length = width
        await wait(1.0)
        log("[E] 구분자 \(Int(width)) — 우리: \(await ownScreenPositions()) | 전체: \(await allExtrasSummary())")
        await capture(menuBarRect(), name: "reverify2_E_\(Int(width))")
    }
    div.length = NSStatusItem.variableLength
    await wait(1.0)
}
