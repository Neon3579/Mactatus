// 권한 없이 확인 가능한 것: 노치 크기, 메뉴바 높이, 메뉴바 층(layer 24/25) 창 목록.
// 실행: swift spikes/probe/geometry.swift
import AppKit
import CoreGraphics

_ = NSApplication.shared

for screen in NSScreen.screens {
    let f = screen.frame
    print("== 화면 \(screen.localizedName)  frame=\(f)  scale=\(screen.backingScaleFactor)")
    print("   safeAreaInsets.top=\(screen.safeAreaInsets.top)")
    if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
        let notch = NSRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: l.height)
        print("   왼쪽 보조 영역=\(l)")
        print("   오른쪽 보조 영역=\(r)")
        print("   → 노치 사각형=\(notch)")
    } else {
        print("   노치 없음")
    }
    print("   메뉴바 높이(frame - visibleFrame 위쪽)=\(f.maxY - screen.visibleFrame.maxY)")
}

let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let menuBarWindows = all.filter { ($0[kCGWindowLayer as String] as? Int).map { $0 == 24 || $0 == 25 } ?? false }
print("\n== layer 24/25 창: \(menuBarWindows.count)개")
var byOwner: [String: Int] = [:]
for w in menuBarWindows {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    byOwner[owner, default: 0] += 1
}
for (owner, n) in byOwner.sorted(by: { $0.value > $1.value }) { print("   \(owner): \(n)") }

print("\n== layer 25 창 위치(화면에 보이는 것만, x 순)")
let onScreen = menuBarWindows.filter {
    ($0[kCGWindowLayer as String] as? Int) == 25 && ($0[kCGWindowIsOnscreen as String] as? Bool) == true
}
for w in onScreen.sorted(by: {
    (($0[kCGWindowBounds as String] as? [String: CGFloat])?["X"] ?? 0) < (($1[kCGWindowBounds as String] as? [String: CGFloat])?["X"] ?? 0)
}) {
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let name = w[kCGWindowName as String] as? String
    print("   x=\(b["X"] ?? -1) w=\(b["Width"] ?? -1) owner=\(w[kCGWindowOwnerName as String] ?? "?") name=\(name ?? "(이름 없음)")")
}
