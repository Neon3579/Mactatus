import AppKit
import DrawerKit
import SwiftUI

/// ⌄ 를 누르면 뜨는 메뉴바 서랍.
struct DrawerView: View {
    let controller: DrawerController

    var body: some View {
        DrawerContent(
            isTrusted: controller.isTrusted,
            items: controller.items,
            notice: controller.notice,
            icon: { controller.icon(for: $0) },
            onOpen: { controller.open($0) },
            onOpenSettings: { controller.openMenuBarSettings() },
            onRequestPermission: { controller.requestAccessibility() })
    }
}

/// 값만 받아 그리는 부분(스냅샷 확인에도 쓴다).
struct DrawerContent: View {
    let isTrusted: Bool
    let items: [MenuBarItem]
    let notice: String?
    let icon: (MenuBarItem) -> NSImage?
    let onOpen: (MenuBarItem) -> Void
    let onOpenSettings: () -> Void
    let onRequestPermission: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메뉴바 서랍").font(.headline)
            if !isTrusted {
                permissionCard
            } else {
                TextField("아이콘 검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                grid(filter(items))
                if let notice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("아이콘을 메뉴바에서 없애려면 시스템 설정 → 메뉴 막대 → \"메뉴 막대에서 허용\"에서 끄세요. 꺼도 여기서 눌러 열 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("메뉴 막대 설정 열기…", action: onOpenSettings)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("손쉬운 사용 권한이 필요해요", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            Text("다른 앱의 메뉴바 아이콘을 찾고 눌러서 열려면 Mactatus에 손쉬운 사용 권한을 켜 주세요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("권한 켜기…", action: onRequestPermission)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func filter(_ items: [MenuBarItem]) -> [MenuBarItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.appName.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func grid(_ items: [MenuBarItem]) -> some View {
        if items.isEmpty {
            Text(query.isEmpty ? "메뉴바 아이콘이 있는 앱이 없어요." : "찾는 아이콘이 없어요.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(68), spacing: 6), count: 4), alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    DrawerTile(item: item, image: icon(item))
                        .onTapGesture { onOpen(item) }
                        .contextMenu {
                            Button("열기") { onOpen(item) }
                            Button("메뉴바에서 숨기기·보이기…", action: onOpenSettings)
                        }
                }
            }
        }
    }
}

private struct DrawerTile: View {
    let item: MenuBarItem
    let image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            Text(item.displayName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 68, height: 58)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.appName == item.displayName ? item.appName : "\(item.displayName) — \(item.appName)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 스냅샷 확인용: 실행 중인 앱으로 그럴듯한 서랍을 그린다.
struct DrawerSnapshotPreview: View {
    let trusted: Bool

    var body: some View {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(9)
        let items = apps.enumerated().map { index, app in
            MenuBarItem(key: "\(app.bundleIdentifier ?? "app")#0", pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                        appName: app.localizedName ?? "앱", title: "", index: 0,
                        frame: CGRect(x: 800 + index * 30, y: 4, width: 24, height: 24), isHidden: false, isOwn: false, isSystem: false)
        }
        return DrawerContent(isTrusted: trusted, items: items, notice: nil,
                             icon: { NSRunningApplication(processIdentifier: $0.pid)?.icon },
                             onOpen: { _ in }, onOpenSettings: {}, onRequestPermission: {})
    }
}
