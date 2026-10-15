import AppKit
import SwiftUI

/// 개발 확인용: `Mactatus --snapshot <폴더>`로 실행하면 한 번 조회한 뒤
/// 팝오버를 라이트·다크 PNG로 그려 저장하고 종료한다(메뉴바를 열지 않고 화면을 확인할 때).
@MainActor
enum DebugSnapshot {
    static var outputDirectory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func write(_ view: some View, to directory: String, name: String, width: CGFloat = 340) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: view
                .frame(width: width)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: appearance)
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(suffix).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
