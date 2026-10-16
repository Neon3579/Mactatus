import AppKit
import CoreKit
import NotchKit
import Observation
import SwiftUI

/// 받는 중인 파일 하나.
public struct DownloadItem: Identifiable, Equatable, Sendable {
    /// 받는 중 파일 경로(Safari .download, Chrome .crdownload, Firefox .part)
    public let id: String
    /// 다 받은 뒤의 이름
    public var name: String
    /// 0...1, 모르면 nil
    public var fraction: Double?
    public var secondsRemaining: Double?

    public init(id: String, name: String, fraction: Double?, secondsRemaining: Double?) {
        self.id = id
        self.name = name
        self.fraction = fraction
        self.secondsRemaining = secondsRemaining
    }
}

/// 받는 중 파일 이름 규칙.
public enum DownloadNames {
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    public static func isPartial(_ url: URL) -> Bool {
        partialExtensions.contains(url.pathExtension.lowercased())
    }

    /// "a.zip.download" → "a.zip". Chrome의 "Unconfirmed 123.crdownload"처럼 원래 이름을 모르는 것은 그대로 둔다.
    public static func finalURL(for url: URL) -> URL {
        guard isPartial(url) else { return url }
        return url.deletingPathExtension()
    }
}

/// ⬇️ 다운로드 모듈: 받는 중이면 노치에 진행률, 다 받으면 잠깐 알리고, 펼치면 진행 목록과 최근 파일.
///
/// Safari·Chrome은 받는 파일의 진행 상황을 Finder에 알리려고 `NSProgress`를 공개한다.
/// 다운로드 폴더에 `Progress.addSubscriber(forFileURL:)`로 구독해 그 진행률을 받는다.
@MainActor
@Observable
public final class DownloadsModule: NotchModule {
    public let id = "downloads"
    public let title = "다운로드"
    public let symbol = "arrow.down.circle"

    public private(set) var active: [DownloadItem] = []
    /// 최근에 다 받은 파일(최신 순, 5개)
    public private(set) var recent: [URL] = []
    /// 다 받음 알림
    public let flash = NotchFlash<URL>()

    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var progresses: [ObjectIdentifier: ProgressBox] = [:]
    @ObservationIgnored private var poll: Task<Void, Never>?
    public let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    public init() {}

    public var compactPriority: Int? {
        if flash.value != nil { return NotchPriority.alert }
        return active.isEmpty ? nil : NotchPriority.download
    }
    public var compactWingWidth: CGFloat { flash.value != nil ? 116 : 44 }

    // MARK: - 켜기·끄기

    public func start() {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let box = ProgressBox(progress)
            Task { @MainActor in self?.published(box) }
            return { Task { @MainActor in self?.unpublished(box) } }
        }
    }

    public func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        poll?.cancel()
        poll = nil
        progresses.removeAll()
        active = []
        flash.clear()
    }

    /// 스냅샷 확인용
    public func showPreview(active: [DownloadItem], recent: [URL], finished: URL?) {
        self.active = active
        self.recent = recent
        if let finished { flash.show(finished, for: .seconds(60)) }
    }

    // MARK: - 진행률

    // 구독으로 받은 Progress는 처음 도착한 순간에는 파일 경로(fileURL)가 비어 있을 때가 있다(macOS 27.0.1에서 확인).
    // 그래서 Progress 객체 자체를 열쇠로 담아 두고, 경로는 읽을 때마다 다시 본다.

    private func published(_ box: ProgressBox) {
        progresses[ObjectIdentifier(box.progress)] = box
        update()
        guard poll == nil else { return }
        // 받는 동안만 0.5초마다 진행률을 읽는다
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.progresses.isEmpty else { break }
                self.update()
            }
            self?.poll = nil
        }
    }

    private func unpublished(_ box: ProgressBox) {
        let progress = box.progress
        let key = ObjectIdentifier(progress)
        let lastFraction = progresses[key]?.lastFraction ?? 0
        let seenURL = progresses[key]?.url
        progresses[key] = nil
        update()
        guard !progress.isCancelled, let url = progress.downloadURL ?? seenURL else { return }
        // 받기가 끝나면 브라우저가 파일 이름에서 .download 등을 뗀다.
        // 진행률이 끝까지 갔거나 그 파일이 생겼으면 다 받은 것(파일 확인은 다운로드 폴더 권한이 있어야 된다)
        let final = DownloadNames.finalURL(for: url)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            let reachedEnd = max(lastFraction, progress.fractionCompleted) >= 0.99
            guard reachedEnd || FileManager.default.fileExists(atPath: final.path), !DownloadNames.isPartial(final) else { return }
            recent.removeAll { $0 == final }
            recent.insert(final, at: 0)
            recent = Array(recent.prefix(5))
            flash.show(final, for: .seconds(4))
            Log.app.info("다운로드 완료 알림: \(final.lastPathComponent, privacy: .public)")
        }
    }

    private func update() {
        let items = progresses.map { key, box -> DownloadItem in
            let progress = box.progress
            let fraction = progress.isIndeterminate || progress.totalUnitCount <= 0 ? nil : progress.fractionCompleted
            if let fraction { box.lastFraction = max(box.lastFraction, fraction) }
            if let url = progress.downloadURL { box.url = url }
            return DownloadItem(
                id: "\(key.hashValue)",
                name: progress.downloadURL.map { DownloadNames.finalURL(for: $0).lastPathComponent } ?? "다운로드",
                fraction: fraction,
                secondsRemaining: progress.estimatedTimeRemaining)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if items != active { active = items }
    }

    // MARK: - 파일 다루기

    public func open(_ url: URL) { NSWorkspace.shared.open(url) }
    public func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    public func openFolder() { NSWorkspace.shared.open(folder) }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView { AnyView(DownloadsCompactLeading(module: self)) }
    public func compactTrailing() -> AnyView { AnyView(DownloadsCompactTrailing(module: self)) }
    public func expanded() -> AnyView { AnyView(DownloadsExpandedView(module: self)) }
}

extension Progress {
    /// 받는 파일 경로. 구독으로 받은 Progress는 `fileURL` 속성이 비어 있고 userInfo에만 들어 있다(macOS 27.0.1에서 확인)
    var downloadURL: URL? { (userInfo[.fileURLKey] as? URL) ?? fileURL }
}

/// 다른 스레드에서 오는 Progress를 메인 액터로 넘기기 위한 상자(읽기·쓰기는 메인에서만).
private final class ProgressBox: @unchecked Sendable {
    let progress: Progress
    /// 지금까지 본 가장 큰 진행률(끝난 뒤에는 Progress 값이 0으로 돌아오기도 해서 따로 둔다)
    var lastFraction: Double = 0
    /// 파일 경로(처음에는 비어 있다가 나중에 들어오기도 해서, 본 적이 있으면 기억한다)
    var url: URL?
    init(_ progress: Progress) { self.progress = progress }
}

// MARK: - 화면

@MainActor
private func fileIcon(_ url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }

/// 여러 개를 받을 때는 전체 평균
private func overall(_ items: [DownloadItem]) -> Double? {
    let known = items.compactMap(\.fraction)
    guard !known.isEmpty else { return nil }
    return known.reduce(0, +) / Double(known.count)
}

/// 미니(왼쪽): 진행 고리 또는 다 받은 파일
struct DownloadsCompactLeading: View {
    let module: DownloadsModule

    var body: some View {
        Group {
            if let finished = module.flash.value {
                HStack(spacing: 5) {
                    Image(nsImage: fileIcon(finished)).resizable().frame(width: 18, height: 18)
                    Text(finished.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)
            } else {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: overall(module.active) ?? 0.15)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold))
                }
                .frame(width: 18, height: 18)
            }
        }
        .foregroundStyle(.white)
    }
}

/// 미니(오른쪽): 진행률 또는 "완료"
struct DownloadsCompactTrailing: View {
    let module: DownloadsModule

    var body: some View {
        Group {
            if module.flash.value != nil {
                Label("완료", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else if let fraction = overall(module.active) {
                Text("\(Int((fraction * 100).rounded()))%")
            } else {
                Text("받는 중")
            }
        }
        .font(.system(size: 11, weight: .medium).monospacedDigit())
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
    }
}

/// 펼침: 받는 중 목록과 최근 파일(누르면 열기, 끌어서 옮기기)
struct DownloadsExpandedView: View {
    let module: DownloadsModule

    var body: some View {
        if module.active.isEmpty && module.recent.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(.secondary)
                Text("받는 중인 파일이 없어요").font(.callout.weight(.medium))
                Button("다운로드 폴더 열기", action: module.openFolder)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(module.active) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Self.status(item)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            if let fraction = item.fraction {
                                ProgressView(value: fraction).tint(.white)
                            } else {
                                ProgressView().progressViewStyle(.linear).tint(.white)
                            }
                        }
                    }
                    ForEach(module.recent, id: \.self) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: fileIcon(url)).resizable().frame(width: 22, height: 22)
                            Text(url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { module.reveal(url) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Finder에서 보기")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { module.open(url) }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .help("누르면 열기, 끌어서 다른 곳에 놓기")
                    }
                }
            }
        }
    }

    static func status(_ item: DownloadItem) -> String {
        var parts: [String] = []
        if let fraction = item.fraction { parts.append("\(Int((fraction * 100).rounded()))%") }
        if let seconds = item.secondsRemaining, seconds.isFinite, seconds > 0 {
            parts.append(seconds < 60 ? "\(Int(seconds))초 남음" : "\(Int(seconds / 60))분 남음")
        }
        return parts.joined(separator: " · ")
    }
}
