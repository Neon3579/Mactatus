import AppKit

/// 서랍에 보여줄 아이콘 그림. 메뉴바 아이콘을 캡처하면 뒤의 배경화면이 같이 찍혀 지저분하고
/// 숨겨진 아이콘은 캡처할 수도 없어서, 그 아이콘을 띄운 앱의 아이콘을 쓴다(화면 기록 권한 불필요).
@MainActor
final class MenuBarIcons {
    private var appIcons: [pid_t: NSImage] = [:]

    func image(for item: MenuBarItem) -> NSImage? {
        if let icon = appIcons[item.pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: item.pid)?.icon
        appIcons[item.pid] = icon
        return icon
    }
}
