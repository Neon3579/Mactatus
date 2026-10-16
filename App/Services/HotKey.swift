import Carbon.HIToolbox

/// 전역 단축키(손쉬운 사용 권한 없이 동작하는 Carbon `RegisterEventHotKey`).
/// 외부 패키지(KeyboardShortcuts) 없이 고정 단축키 하나(⌘⇧V)만 쓰므로 직접 등록한다.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: 가상 키 코드(예: `kVK_ANSI_V`)
    ///   - modifiers: Carbon 수정 키(예: `cmdKey | shiftKey`)
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // 단축키 이벤트는 메인 스레드(앱 이벤트 대상)로 온다
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4D54_5453), id: 1) // 'MTTS'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
