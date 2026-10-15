// 메뉴바 아이콘을 ⌘-끌기로 옮긴다(사람이 하는 것과 같은 방식). 손쉬운 사용 권한이 필요하다.
// macOS 27.0.1에서 합성한 ⌘-끌기로 아이콘 순서가 바뀌는 것을 확인함.
import AppKit
import CoreGraphics

enum EventSynth {
    private static func post(_ type: CGEventType, _ point: CGPoint, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = flags
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
    }

    private static func commandKey(down: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: down)
        event?.flags = down ? .maskCommand : []
        event?.post(tap: .cghidEventTap)
    }

    /// 지금 커서 위치(CG 좌표).
    @MainActor static var cursor: CGPoint {
        let p = NSEvent.mouseLocation
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: height - p.y)
    }

    /// from에서 to로 ⌘를 누른 채 끈다. 끝나면 커서를 원래 자리로 돌려놓는다.
    @MainActor static func commandDrag(from: CGPoint, to: CGPoint) async {
        let original = cursor
        commandKey(down: true)
        try? await Task.sleep(for: .milliseconds(50))
        post(.mouseMoved, from, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(80))
        post(.leftMouseDown, from, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(250))
        let steps = 15
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), flags: .maskCommand)
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseUp, to, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(50))
        commandKey(down: false)
        CGWarpMouseCursorPosition(original)
    }
}
