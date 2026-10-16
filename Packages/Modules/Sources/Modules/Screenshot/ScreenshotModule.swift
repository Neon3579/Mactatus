import AppKit
import NotchKit
import Observation
import SwiftUI

/// 📸 스크린샷: 새 스크린샷이 저장되면 노치에 썸네일을 잠깐 보여주고, 펼치면 최근 스크린샷을 복사·옮기기·마크업·삭제.
///
/// Spotlight(`NSMetadataQuery`, `kMDItemIsScreenCapture == 1`)로 macOS 스크린샷 저장 위치(기본 데스크톱)를 지켜본다.
/// macOS 스크린샷의 떠 있는 미리보기가 사라진 뒤(약 5초) 파일이 저장되므로 그때 알린다.
@MainActor
@Observable
public final class ScreenshotModule: NotchModule {
    public let id = "screenshot"
    public let title = "스크린샷"
    public let symbol = "camera.viewfinder"

    /// 최근 스크린샷(최신 순, 8개)
    public private(set) var recent: [URL] = []
    /// 새 스크린샷 알림
    public let flash = NotchFlash<URL>()
    /// 새 스크린샷이 저장될 때(클립보드 기록에 넣는 데 쓴다)
    @ObservationIgnored public var onNewScreenshot: ((URL) -> Void)?

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var gathered = false

    public init() {}

    public var compactPriority: Int? { flash.value != nil ? NotchPriority.alert : nil }
    public var compactWingWidth: CGFloat { 84 }

    /// macOS 스크린샷 저장 위치(시스템 설정 → 스크린샷 옵션). 없으면 데스크톱
    public static var saveFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 켜기·끄기

    public func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [Self.saveFolder]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.3
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(announceNew: false) }
        })
        observers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(announceNew: true) }
        })
        self.query = query
        query.start()
    }

    public func stop() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        flash.clear()
    }

    /// 스냅샷 확인용
    public func showPreview(_ urls: [URL], flashing: URL?) {
        recent = urls
        if let flashing { flash.show(flashing, for: .seconds(60)) }
    }

    private func reload(announceNew: Bool) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let urls = (0..<min(query.resultCount, 8)).compactMap { index -> URL? in
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
            return URL(fileURLWithPath: path)
        }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        // 처음 모은 결과는 이미 있던 것들이라 알리지 않는다. 그 뒤에 맨 앞에 새로 생긴 것만 알린다
        if announceNew, gathered, let newest = urls.first, newest != recent.first {
            flash.show(newest, for: .seconds(4))
            onNewScreenshot?(newest)
        }
        gathered = true
        recent = urls
    }

    // MARK: - 동작

    public func copy(_ url: URL) { FileActions.copy([url]) }

    /// 미리보기 앱에서 열어 마크업한다
    public func markup(_ url: URL) {
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            FileActions.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    /// 휴지통으로 옮긴다(완전히 지우지는 않음)
    public func moveToTrash(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { [weak self] _, _ in
            Task { @MainActor in
                self?.recent.removeAll { $0 == url }
                if self?.flash.value == url { self?.flash.clear() }
            }
        }
    }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView {
        AnyView(Group {
            if let url = flash.value {
                FileThumbnail(url: url, size: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10))
    }

    public func compactTrailing() -> AnyView {
        AnyView(Text("스크린샷")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 10))
    }

    public func expanded() -> AnyView { AnyView(ScreenshotView(module: self)) }
}

/// 펼침: 최근 스크린샷. 누르면 훑어보기, 끌어서 옮기기, 우클릭으로 복사·마크업·삭제.
struct ScreenshotView: View {
    let module: ScreenshotModule

    var body: some View {
        if module.recent.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "camera.viewfinder").font(.title2).foregroundStyle(.secondary)
                Text("최근 스크린샷이 없어요").font(.callout.weight(.medium))
                Text("⌘⇧3·⌘⇧4·⌘⇧5로 찍으면 여기에 보여요.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(module.recent, id: \.self) { url in
                        VStack(spacing: 6) {
                            FileThumbnail(url: url, size: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .shadow(radius: 2)
                            HStack(spacing: 12) {
                                button("doc.on.doc", "복사") { module.copy(url) }
                                button("pencil.tip.crop.circle", "마크업") { module.markup(url) }
                                button("trash", "휴지통으로") { module.moveToTrash(url) }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { QuickLook.shared.show(module.recent, index: module.recent.firstIndex(of: url) ?? 0) }
                        .onDrag { FileActions.provider(url) }
                        .contextMenu {
                            Button("훑어보기") { QuickLook.shared.show([url]) }
                            Button("복사") { module.copy(url) }
                            Button("마크업") { module.markup(url) }
                            Button("Finder에서 보기") { FileActions.reveal([url]) }
                            Divider()
                            Button("휴지통으로 이동") { module.moveToTrash(url) }
                        }
                        .help("누르면 훑어보기, 끌어서 다른 곳에 놓기")
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}
