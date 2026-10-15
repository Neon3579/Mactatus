import AppKit
import SwiftUI

/// 재생 중인 앱의 아이콘(앨범아트가 없을 때 대신 쓴다)
@MainActor
private func appIcon(_ bundleID: String?) -> NSImage? {
    guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

@MainActor
private func appName(_ bundleID: String?) -> String? {
    guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

/// 앨범아트(없으면 앱 아이콘, 그것도 없으면 음표)
struct MediaArtwork: View {
    let artwork: NSImage?
    let bundleID: String?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = appIcon(bundleID) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).padding(size * 0.08)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// 미니: 노치 왼쪽 날개의 앨범아트
struct MediaCompactArtwork: View {
    let module: MediaModule

    var body: some View {
        MediaArtwork(artwork: module.artwork, bundleID: module.nowPlaying?.appBundleID, size: 20, radius: 5)
    }
}

/// 미니: 노치 오른쪽 날개의 이퀄라이저(재생 중일 때만 움직인다, 동작 줄이기를 켜면 멈춘 막대).
/// 막대 움직임은 Core Animation 반복 애니메이션이라 화면 합성기가 그린다(앱이 매 프레임 다시 그리지 않아 CPU를 거의 안 씀).
struct MediaEqualizer: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EqualizerBars(animating: isPlaying && !reduceMotion)
            .frame(width: 17, height: 14)
            .accessibilityLabel(isPlaying ? "재생 중" : "일시 정지")
    }
}

private struct EqualizerBars: NSViewRepresentable {
    let animating: Bool

    func makeNSView(context: Context) -> EqualizerView { EqualizerView() }

    func updateNSView(_ view: EqualizerView, context: Context) {
        view.setAnimating(animating)
    }
}

final class EqualizerView: NSView {
    private var bars: [CALayer] = []
    private var animating = false
    /// 막대마다 다른 속도로 오르내린다
    private static let durations: [CFTimeInterval] = [0.42, 0.31, 0.55, 0.37]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            bar.cornerRadius = 1.25
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 2.5, height: bounds.height)
            bar.position = CGPoint(x: 1.25 + CGFloat(index) * 4.5, y: bounds.midY)
            if bar.animation(forKey: "level") == nil { bar.transform = CATransform3DMakeScale(1, 0.3, 1) }
        }
    }

    func setAnimating(_ value: Bool) {
        guard value != animating else { return }
        animating = value
        for (index, bar) in bars.enumerated() {
            if value {
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = 0.3
                animation.toValue = 1.0
                animation.duration = Self.durations[index]
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.timeOffset = Double(index) * 0.13
                bar.add(animation, forKey: "level")
            } else {
                bar.removeAnimation(forKey: "level")
                bar.transform = CATransform3DMakeScale(1, 0.3, 1)
            }
        }
    }
}

/// 펼침: 곡 정보, 재생 위치, 재생 제어
struct MediaExpandedView: View {
    let module: MediaModule

    var body: some View {
        if !module.isAvailable {
            message("음악 정보를 읽을 수 없어요", detail: "mediaremote-adapter가 앱 안에 없어요. scripts/build.sh로 다시 빌드해 주세요.")
        } else if let now = module.nowPlaying {
            HStack(alignment: .top, spacing: 14) {
                Button(action: module.openPlayer) {
                    MediaArtwork(artwork: module.artwork, bundleID: now.appBundleID, size: 92, radius: 12)
                }
                .buttonStyle(.plain)
                .help("\(appName(now.appBundleID) ?? "재생 중인 앱") 열기")

                VStack(alignment: .leading, spacing: 2) {
                    Text(now.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text([now.artist, now.album].compactMap { $0 }.joined(separator: " — "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    MediaProgress(module: module, now: now)
                    MediaControls(module: module, isPlaying: now.isPlaying)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            message("재생 중인 음악이 없어요", detail: "Music, Spotify, 브라우저 등에서 재생하면 여기에 보여요.")
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 재생 위치 막대(누르면 그 위치로 이동)와 시간
struct MediaProgress: View {
    let module: MediaModule
    let now: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = now.elapsed(at: context.date) ?? 0
            let duration = now.duration
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let fraction = duration.map { $0 > 0 ? min(elapsed / $0, 1) : 0 } ?? 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(0.85)).frame(width: proxy.size.width * fraction)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let duration, duration > 0 else { return }
                        module.seek(to: duration * min(max(location.x / proxy.size.width, 0), 1))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(duration.map { "-" + Self.format(max($0 - elapsed, 0)) } ?? "")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("재생 위치")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 이전·재생/일시정지·다음
struct MediaControls: View {
    let module: MediaModule
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 22) {
            button("backward.fill", label: "이전 곡", size: 15, action: module.previous)
            button(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "일시 정지" : "재생", size: 22, action: module.togglePlayPause)
            button("forward.fill", label: "다음 곡", size: 15, action: module.next)
        }
    }

    private func button(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
