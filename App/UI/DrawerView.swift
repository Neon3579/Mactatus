import AppKit
import DrawerKit
import SwiftUI

/// ⌄ 를 누르면 뜨는 메뉴바 서랍.
struct DrawerView: View {
    let controller: DrawerController

    var body: some View {
        DrawerContent(
            isTrusted: controller.isTrusted,
            drawerItems: controller.drawerItems,
            menuBarItems: controller.menuBarItems,
            notice: controller.notice,
            isBusy: controller.isBusy,
            isEditing: controller.isEditing,
            icon: { controller.icon(for: $0) },
            onOpen: { controller.open($0) },
            onPutIn: { item in Task { await controller.putInDrawer(item) } },
            onTakeOut: { item in Task { await controller.takeOut(item) } },
            onRequestPermission: { controller.requestAccessibility() },
            onToggleEditing: { controller.isEditing ? controller.stopEditing() : controller.startEditing() },
            onTileDragChanged: { controller.tileDragChanged($0) },
            onTileDragEnded: { controller.tileDragEnded($0) })
    }
}

/// 값만 받아 그리는 부분(스냅샷 확인에도 쓴다).
struct DrawerContent: View {
    let isTrusted: Bool
    let drawerItems: [MenuBarItem]
    let menuBarItems: [MenuBarItem]
    let notice: String?
    let isBusy: Bool
    var isEditing = false
    let icon: (MenuBarItem) -> NSImage?
    let onOpen: (MenuBarItem) -> Void
    let onPutIn: (MenuBarItem) -> Void
    let onTakeOut: (MenuBarItem) -> Void
    let onRequestPermission: () -> Void
    var onToggleEditing: () -> Void = {}
    var onTileDragChanged: (MenuBarItem) -> Void = { _ in }
    var onTileDragEnded: (MenuBarItem) -> Void = { _ in }

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("메뉴바 서랍").font(.headline)
                Spacer()
                if isBusy { ProgressView().controlSize(.small) }
                if isTrusted {
                    Button(isEditing ? "완료" : "편집", action: onToggleEditing)
                        .buttonStyle(.borderless)
                        .fontWeight(isEditing ? .semibold : .regular)
                        .help(isEditing ? "편집 끝내기(Esc)" : "메뉴바 아이콘을 ⌘ 없이 끌어 옮기기")
                }
            }
            if isEditing {
                Label("메뉴바 아이콘을 끌어 순서를 바꾸거나 이 창으로 끌어 넣어요. 이 창의 아이콘은 메뉴바로 끌어내요.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isTrusted {
                permissionCard
            } else {
                TextField("아이콘 검색", text: $query)
                    .textFieldStyle(.roundedBorder)
                section("서랍", items: filter(drawerItems), inDrawer: true, empty: "서랍이 비어 있어요. 아래 아이콘을 우클릭해 넣어 보세요.")
                section("메뉴바", items: filter(menuBarItems.filter { !$0.isSystem }), inDrawer: false, empty: nil)
                if let notice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("아이콘을 누르면 원래 메뉴가 열려요. 메뉴바로 끌어내거나 우클릭으로 넣고 꺼낼 수 있어요. ⌄ 우클릭 → 메뉴 막대 편집.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("손쉬운 사용 권한이 필요해요", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            Text("다른 앱의 메뉴바 아이콘을 찾고, 눌러서 열고, 서랍으로 옮기려면 Mactatus에 손쉬운 사용 권한을 켜 주세요.")
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
    private func section(_ title: String, items: [MenuBarItem], inDrawer: Bool, empty: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(items.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if items.isEmpty, let empty {
                Text(empty).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(68), spacing: 6), count: 4), alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        DrawerTile(item: item, image: icon(item))
                            .onTapGesture { onOpen(item) }
                            .gesture(DragGesture(minimumDistance: 6)
                                .onChanged { _ in onTileDragChanged(item) }
                                .onEnded { _ in onTileDragEnded(item) })
                            .contextMenu {
                                Button("열기") { onOpen(item) }
                                if inDrawer {
                                    Button("메뉴바로 꺼내기") { onTakeOut(item) }
                                } else {
                                    Button("서랍에 넣기") { onPutIn(item) }
                                }
                            }
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
    var editing = false

    var body: some View {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(9)
        let items = apps.enumerated().map { index, app in
            MenuBarItem(key: "\(app.bundleIdentifier ?? "app")#0", pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                        appName: app.localizedName ?? "앱", title: "", index: 0,
                        frame: CGRect(x: 800 + index * 30, y: 4, width: 24, height: 24), isHidden: index < 5, isOwn: false, isSystem: false)
        }
        return DrawerContent(isTrusted: trusted, drawerItems: items.filter { $0.isHidden }, menuBarItems: items.filter { !$0.isHidden },
                             notice: nil, isBusy: false, isEditing: editing,
                             icon: { NSRunningApplication(processIdentifier: $0.pid)?.icon },
                             onOpen: { _ in }, onPutIn: { _ in }, onTakeOut: { _ in }, onRequestPermission: {})
    }
}
