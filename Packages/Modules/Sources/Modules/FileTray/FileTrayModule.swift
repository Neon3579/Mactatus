import AppKit
import NotchKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// 📁 파일 트레이: 파일을 끌어 노치에 놓아 잠깐 담아 두고, 필요할 때 끌어서 꺼내거나 AirDrop으로 보낸다.
@MainActor
@Observable
public final class FileTrayModule: NotchModule {
    public let id = "tray"
    public let title = "파일 트레이"
    public let symbol = "tray"

    public private(set) var items: [TrayItem] = []
    /// 담음 알림(담은 개수)
    public let flash = NotchFlash<Int>()
    /// true면 원본 대신 복사본을 보관한다
    public var keepsCopies = false
    /// 담은 지 이 시간이 지나면 뺀다(0이면 안 뺌)
    public var clearAfterHours = 24

    @ObservationIgnored private let disk = TrayDisk()
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init() {}

    public var compactPriority: Int? { flash.value != nil ? NotchPriority.alert : nil }
    public var compactWingWidth: CGFloat { 72 }
    public var acceptsFileDrops: Bool { true }

    // MARK: - 켜기·끄기

    public func start() {
        guard timer == nil else { return }
        items = disk.load().compactMap(disk.resolve)
        clearExpired()
        // 한 시간마다 오래된 것을 비운다
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                self?.clearExpired()
            }
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        flash.clear()
    }

    /// 스냅샷 확인용
    public func showPreview(_ urls: [URL], flashCount: Int?) {
        items = urls.map { TrayItem(id: UUID(), path: $0.path, bookmark: nil, isCopy: false, addedAt: .now) }
        if let flashCount { flash.show(flashCount, for: .seconds(60)) }
    }

    // MARK: - 담기·빼기

    public func add(_ urls: [URL]) {
        let new = urls.filter { $0.isFileURL }.compactMap { disk.makeItem(for: $0, copy: keepsCopies) }
        guard !new.isEmpty else { return }
        items = TrayRules.adding(new, to: items)
        disk.save(items)
        flash.show(new.count, for: .seconds(2))
    }

    /// 끌어 놓은 것 받기
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = (object as? NSURL) as URL? else { return }
                Task { @MainActor [weak self] in self?.add([url]) }
            }
        }
        return true
    }

    public func remove(_ item: TrayItem) {
        disk.discard(item)
        ThumbnailCache.shared.forget(item.url)
        items.removeAll { $0.id == item.id }
        disk.save(items)
    }

    public func removeAll() {
        items.forEach(disk.discard)
        items = []
        disk.save(items)
    }

    /// 끌어서 꺼낸 뒤 원본이 옮겨졌으면 목록을 맞춘다
    func refresh() {
        let resolved = items.compactMap(disk.resolve)
        if resolved != items {
            items = resolved
            disk.save(items)
        }
    }

    private func clearExpired() {
        let expired = TrayRules.expired(items, hours: clearAfterHours, now: .now)
        guard !expired.isEmpty else { return }
        expired.forEach(disk.discard)
        items.removeAll { item in expired.contains { $0.id == item.id } }
        disk.save(items)
    }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView {
        AnyView(Image(systemName: "tray.and.arrow.down.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10))
    }

    public func compactTrailing() -> AnyView {
        AnyView(Text("\(flash.value ?? 0)개 담음")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10))
    }

    public func expanded() -> AnyView { AnyView(FileTrayView(module: self)) }
}

/// 펼침: 담긴 파일 썸네일. 여기로 파일을 끌어 놓으면 담기고, 썸네일을 끌어서 꺼낸다.
struct FileTrayView: View {
    let module: FileTrayModule
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                    Text("파일을 여기로 끌어 놓으세요").font(.callout.weight(.medium))
                    Text("잠깐 담아 두었다가 끌어서 꺼내거나 AirDrop으로 보낼 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(module.items) { item in
                            TrayTile(module: module, item: item)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button("모두 AirDrop") { FileActions.airDrop(module.items.map(\.url)) }
                    Button("Finder에서 보기") { FileActions.reveal(module.items.map(\.url)) }
                    Spacer()
                    Button("모두 비우기", role: .destructive) { module.removeAll() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(targeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.15)))
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in module.handleDrop(providers) }
        .onAppear { module.refresh() }
    }
}

private struct TrayTile: View {
    let module: FileTrayModule
    let item: TrayItem

    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: item.url, size: 52)
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileActions.open(item.url) }
        .onTapGesture { QuickLook.shared.show(module.items.map(\.url), index: module.items.firstIndex(of: item) ?? 0) }
        .onDrag { FileActions.provider(item.url) }
        .contextMenu {
            Button("훑어보기") { QuickLook.shared.show([item.url]) }
            Button("열기") { FileActions.open(item.url) }
            Button("Finder에서 보기") { FileActions.reveal([item.url]) }
            Button("AirDrop…") { FileActions.airDrop([item.url]) }
            Button("복사") { FileActions.copy([item.url]) }
            Divider()
            Button("트레이에서 빼기") { module.remove(item) }
        }
        .help("누르면 훑어보기, 두 번 누르면 열기, 끌어서 꺼내기")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
