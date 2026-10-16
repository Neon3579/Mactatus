import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI

/// 파일 썸네일(훑어보기 미리보기, 없으면 파일 아이콘). 한 번 만든 것은 기억한다.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [URL: NSImage] = [:]
    private var pending: Set<URL> = []

    func image(for url: URL, size: CGFloat, onReady: @escaping @MainActor () -> Void) -> NSImage {
        if let image = images[url] { return image }
        if !pending.contains(url) {
            pending.insert(url)
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                let image = thumbnail?.nsImage
                Task { @MainActor in
                    self.pending.remove(url)
                    if let image {
                        self.images[url] = image
                        onReady()
                    }
                }
            }
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func forget(_ url: URL) { images[url] = nil }
}

/// 썸네일을 그리고, 만들어지면 다시 그린다.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var version = 0

    var body: some View {
        let _ = version
        Image(nsImage: ThumbnailCache.shared.image(for: url, size: size * 2) { version += 1 })
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 훑어보기(스페이스 바 미리보기) 창.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()
    private var urls: [URL] = []

    func show(_ urls: [URL], index: Int = 0) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = index
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}

/// 파일 공통 동작.
@MainActor
enum FileActions {
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
    static func reveal(_ urls: [URL]) { NSWorkspace.shared.activateFileViewerSelecting(urls) }

    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    /// 클립보드에 파일(이미지면 그림도 함께)을 넣는다.
    static func copy(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = urls.map { $0 as NSURL }
        if urls.count == 1, let image = NSImage(contentsOf: urls[0]) { objects.append(image) }
        pasteboard.writeObjects(objects)
    }

    /// 끌어서 옮기기용
    static func provider(_ url: URL) -> NSItemProvider {
        NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }
}
