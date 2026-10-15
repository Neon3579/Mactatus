import AppKit
import ApplicationServices
import IOBluetooth

@_cdecl("spike_run")
public func spikeRun(_ name: UnsafePointer<CChar>, _ logPath: UnsafePointer<CChar>, _ extra: UnsafePointer<CChar>) {
    let test = String(cString: name)
    let extraArg = String(cString: extra)
    let path = String(cString: logPath)
    Log.open(path)
    outDir = (path as NSString).deletingLastPathComponent
    log("테스트: \(test) | \(ProcessInfo.processInfo.operatingSystemVersionString)")
    log("권한: 손쉬운 사용=\(AXIsProcessTrusted()) 화면 기록=\(CGPreflightScreenCaptureAccess()) 이벤트 전송=\(CGPreflightPostEventAccess())")

    Task { @MainActor in
        switch test {
        case "perm": await testPermissions()
        case "axlist": await testAXList()
        case "items": await testItems()
        case "notch": await testNotch(extraSeconds: Double(extraArg) ?? 10)
        case "bt": await testBluetooth(seconds: Double(extraArg) ?? 60)
        case "media": await testMedia()
        case "native": await testNative()
        case "press": await testPressApp(extraArg)
        default: log("알 수 없는 테스트: \(test)")
        }
        log("끝")
        try? Log.handle?.synchronize()
        exit(0)
    }
}

@MainActor func testPermissions() async {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    log("손쉬운 사용 요청 → 현재 \(AXIsProcessTrustedWithOptions(options))")
    log("화면 기록 요청 → 현재 \(CGRequestScreenCaptureAccess())")
    log("이벤트 전송 요청 → 현재 \(CGRequestPostEventAccess())")
    let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    log("블루투스 요청(페어링 기기 조회) → \(paired.count)개")
    await wait(8)
}

@MainActor func testAXList() async {
    guard AXIsProcessTrusted() else { log("손쉬운 사용 권한 없음 → 중단"); return }
    let result = await Task.detached { () -> [String] in
        var lines: [String] = []
        var total = 0
        for app in NSWorkspace.shared.runningApplications {
            let items = extrasItems(pid: app.processIdentifier)
            guard !items.isEmpty else { continue }
            total += items.count
            lines.append("앱 \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")]: \(items.count)개")
            for el in items {
                lines.append("    \(axLabel(el)) frame=\(fmt(axFrame(el))) actions=\(axActions(el))")
            }
        }
        lines.append("AXExtrasMenuBar 아이템 합계: \(total)")
        lines.append("--- 메뉴바 위치별 주인(hit test, y=12)")
        lines += hitTestMenuBar()
        return lines
    }.value
    result.forEach(log)
    await capture(menuBarRect(), name: "axlist_menubar")
}
