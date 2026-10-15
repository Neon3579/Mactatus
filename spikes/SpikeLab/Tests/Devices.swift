// 블루투스 연결 알림·배터리, MediaRemote 직접 호출 검증.
import AppKit
import IOBluetooth

final class BTWatcher: NSObject {
    var notes: [IOBluetoothUserNotification] = []

    @objc func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        log("▶ 연결: \(device.name ?? "?") | \(batteryInfo(device))")
        if let n = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:))) {
            notes.append(n)
        }
    }

    @objc func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        log("▶ 연결 끊김: \(device.name ?? "?")")
    }
}
nonisolated(unsafe) let btWatcher = BTWatcher()

/// IOBluetoothDevice의 비공개 배터리 속성(있을 때만)을 읽는다.
func batteryInfo(_ d: IOBluetoothDevice) -> String {
    let keys = ["batteryPercentLeft", "batteryPercentRight", "batteryPercentCase",
                "batteryPercentSingle", "batteryPercentCombined", "headsetBattery"]
    let found = keys.compactMap { key -> String? in
        guard d.responds(to: NSSelectorFromString(key)) else { return nil }
        return "\(key)=\(d.value(forKey: key).map { "\($0)" } ?? "nil")"
    }
    return found.isEmpty ? "배터리 속성 없음" : found.joined(separator: " ")
}

@MainActor func testBluetooth(seconds: Double) async {
    let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    log("페어링 기기 \(paired.count)개")
    for d in paired { log("   \(d.name ?? "?") 연결=\(d.isConnected()) | \(batteryInfo(d))") }
    let note = IOBluetoothDevice.register(forConnectNotifications: btWatcher, selector: #selector(BTWatcher.connected(_:device:)))
    log("연결 알림 등록: \(note != nil) — \(Int(seconds))초 동안 기다림")
    var t = 0.0
    while t < seconds {
        await wait(5)
        t += 5
    }
    for d in paired where d.isConnected() { log("   끝날 때 연결됨: \(d.name ?? "?") | \(batteryInfo(d))") }
}

@MainActor func testMedia() async {
    let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, url) else { log("MediaRemote 로드 실패"); return }
    typealias InfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    typealias BoolFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
        unsafeBitCast(p, to: InfoFn.self)(DispatchQueue.main) { dict in
            let info = dict as? [String: Any] ?? [:]
            log("직접 호출 NowPlayingInfo: 키 \(info.count)개, 제목 있음=\(info["kMRMediaRemoteNowPlayingInfoTitle"] != nil)")
        }
    } else {
        log("함수 없음: MRMediaRemoteGetNowPlayingInfo")
    }
    if let p = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) {
        unsafeBitCast(p, to: BoolFn.self)(DispatchQueue.main) { playing in log("직접 호출 IsPlaying: \(playing)") }
    }
    await wait(3)
}
