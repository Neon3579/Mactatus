import AppKit
import CoreKit
import NotchKit
import Observation
import SwiftUI

/// 🎵 음악 모듈: 재생 중이면 노치 양옆에 앨범아트와 이퀄라이저, 펼치면 곡 정보와 재생 제어.
@MainActor
@Observable
public final class MediaModule: NotchModule {
    public let id = "media"
    public let title = "음악"
    public let symbol = "music.note"

    public private(set) var nowPlaying: NowPlaying?
    public private(set) var artwork: NSImage?
    /// mediaremote-adapter가 앱 안에 있는지
    public private(set) var isAvailable: Bool

    @ObservationIgnored private let adapter: MediaAdapter?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var artworkSource: Data?

    public init(paths: MediaAdapter.Paths? = .bundled()) {
        adapter = paths.map(MediaAdapter.init)
        isAvailable = paths != nil
    }

    /// 재생 중일 때만 미니로 보인다(멈춰 있으면 노치를 비워 둔다)
    public var compactPriority: Int? { nowPlaying?.isPlaying == true ? NotchPriority.media : nil }

    // MARK: - 켜기·끄기

    public func start() {
        guard task == nil, let adapter else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                for await update in await adapter.updates() {
                    self?.apply(update)
                }
                // perl이 끝났다(잠자기·오류 등) → 잠깐 쉬고 다시 띄운다
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if let adapter { Task { await adapter.stop() } }
        apply(nil)
    }

    private func apply(_ update: NowPlaying?) {
        if update?.artworkData != artworkSource {
            artworkSource = update?.artworkData
            artwork = update?.artworkData.flatMap(NSImage.init(data:))
        }
        if update?.isPlaying != nowPlaying?.isPlaying || update?.bundleID != nowPlaying?.bundleID {
            Log.app.info("음악: \(update?.appBundleID ?? "재생 없음", privacy: .public) \(update?.isPlaying == true ? "재생 중" : "멈춤", privacy: .public), 앨범아트 \(self.artwork != nil ? "있음" : "없음", privacy: .public)")
        }
        if update != nowPlaying { nowPlaying = update }
    }

    /// 스냅샷 확인용: 정해진 재생 정보를 보여준다.
    public func showPreview(_ value: NowPlaying?, artwork: NSImage? = nil) {
        isAvailable = true
        nowPlaying = value
        self.artwork = artwork
    }

    // MARK: - 제어

    public func togglePlayPause() {
        // 누르자마자 아이콘이 바뀌게 먼저 반영하고, 실제 상태는 다음 알림으로 맞춘다
        if var current = nowPlaying {
            current.elapsed = current.elapsed(at: .now)
            current.timestamp = .now
            current.isPlaying.toggle()
            nowPlaying = current
        }
        send(.togglePlayPause)
    }

    public func next() { send(.next) }
    public func previous() { send(.previous) }

    public func seek(to seconds: TimeInterval) {
        guard let adapter else { return }
        if var current = nowPlaying {
            current.elapsed = seconds
            current.timestamp = .now
            nowPlaying = current
        }
        Task { await adapter.seek(to: seconds) }
    }

    private func send(_ command: MediaCommand) {
        guard let adapter else { return }
        Task { await adapter.send(command) }
    }

    /// 재생 중인 앱 열기
    public func openPlayer() {
        guard let bundleID = nowPlaying?.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 노치 화면

    public func compactLeading() -> AnyView { AnyView(MediaCompactArtwork(module: self)) }
    public func compactTrailing() -> AnyView { AnyView(MediaEqualizer(isPlaying: nowPlaying?.isPlaying == true)) }
    public func expanded() -> AnyView { AnyView(MediaExpandedView(module: self)) }
}
