import AppKit
import DrawerKit
import Modules
import SwiftUI

/// ⌘⇧V 클립보드 기록 창: 검색하고 ↑↓로 골라 ↩로 앞에 있던 앱에 붙여넣는다.
/// 창은 앱을 앞으로 가져오지 않는 패널이라, 닫으면 원래 앱이 그대로 앞에 있다.
@MainActor
final class ClipboardPopup {
    private let module: ClipboardModule
    private let panel = MenuBarPanel()
    private var previousApp: NSRunningApplication?

    init(module: ClipboardModule) {
        self.module = module
    }

    func toggle() {
        if panel.isVisible {
            panel.close()
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let width: CGFloat = 400
        let anchor = (screen?.frame.midX ?? NSEvent.mouseLocation.x) - width / 2
        panel.show(content: AnyView(ClipboardPopupView(module: module, width: width,
                                                       onPaste: { [weak self] item in self?.paste(item) })),
                   anchorX: anchor, edge: .leading) {}
    }

    /// 다시 복사하고 원래 앱에 ⌘V를 보낸다(손쉬운 사용 권한 필요).
    private func paste(_ item: ClipboardItem) {
        module.copy(item)
        panel.close()
        let target = previousApp
        Task {
            target?.activate()
            try? await Task.sleep(for: .milliseconds(120))
            Self.sendCommandV()
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown) // 9 = V
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

private struct ClipboardPopupView: View {
    let module: ClipboardModule
    let width: CGFloat
    let onPaste: (ClipboardItem) -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let list = Array(ClipboardRules.filtered(module.items, query: query).prefix(40))
        VStack(alignment: .leading, spacing: 8) {
            TextField("클립보드 검색", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, max(list.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, 0)
                    return .handled
                }
                .onKeyPress(.return) {
                    if list.indices.contains(selection) { onPaste(list[selection]) }
                    return .handled
                }
            if list.isEmpty {
                Text(module.items.isEmpty ? "아직 기록이 없어요. 무언가를 복사해 보세요." : "찾는 기록이 없어요.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(module: module, item: item)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(index == selection ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .contentShape(Rectangle())
                                    .onTapGesture { onPaste(item) }
                                    .contextMenu {
                                        Button("붙여넣기") { onPaste(item) }
                                        Button("복사만") { module.copy(item) }
                                        Button(item.isPinned ? "고정 풀기" : "고정") { module.togglePin(item) }
                                        Divider()
                                        Button("기록에서 지우기") { module.delete(item) }
                                    }
                                    .id(index)
                            }
                        }
                    }
                    .frame(height: 300)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
            Text("↩ 붙여넣기 · ↑↓ 고르기 · esc 닫기 · 우클릭으로 고정")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: width)
        .onAppear {
            selection = 0
            searchFocused = true
        }
        .onChange(of: query) { selection = 0 }
    }
}
