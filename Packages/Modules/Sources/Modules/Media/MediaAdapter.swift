// 비공식: macOS 15.4부터 다른 개발사 앱이 MediaRemote를 직접 부르면 빈 결과가 온다(macOS 27.0.1에서도 같음).
// Apple이 서명한 /usr/bin/perl이 mediaremote-adapter 프레임워크를 불러 대신 읽고 JSON 한 줄씩 내보낸다.
// macOS 27.0.1에서 확인(docs/spike-results.md 4번). 실패하면 음악 모듈만 "읽을 수 없음"으로 표시한다.
import CoreKit
import Foundation
import Synchronization

/// 재생 제어 명령(mediaremote-adapter `send` ID)
public enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
}

/// mediaremote-adapter 실행기.
public actor MediaAdapter {
    /// 앱 묶음 안의 스크립트·프레임워크 위치
    public struct Paths: Sendable {
        public let script: URL
        public let framework: URL

        public init(script: URL, framework: URL) {
            self.script = script
            self.framework = framework
        }

        /// `Contents/Resources/mediaremote-adapter.pl`, `Contents/Frameworks/MediaRemoteAdapter.framework`(scripts/build.sh가 넣는다)
        public static func bundled(in bundle: Bundle = .main) -> Paths? {
            guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let framework = bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
                  FileManager.default.fileExists(atPath: framework.path) else { return nil }
            return Paths(script: script, framework: framework)
        }
    }

    private let paths: Paths
    private var process: Process?
    private var cleanedOrphans = false
    /// 앱이 끝날 때 동기로 끄려고 지금 띄운 perl의 pid를 따로 둔다
    private static let runningPID = Mutex<pid_t>(0)

    public init(paths: Paths) {
        self.paths = paths
    }

    /// 재생 정보가 바뀔 때마다 받는다. perl이 끝나면 스트림도 끝난다(다시 부르면 새로 띄움).
    public func updates() -> AsyncStream<NowPlaying?> {
        stop()
        cleanOrphansOnce()
        let (stream, continuation) = AsyncStream<NowPlaying?>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path, "stream", "--micros", "--debounce=150"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.app.error("mediaremote-adapter 실행 실패: \(error.localizedDescription, privacy: .public)")
            continuation.finish()
            return stream
        }
        self.process = process
        Self.runningPID.withLock { $0 = process.processIdentifier }
        let handle = out.fileHandleForReading
        let reader = Task.detached {
            var parser = NowPlayingStream()
            do {
                for try await line in handle.bytes.lines {
                    do {
                        continuation.yield(try parser.apply(line: Data(line.utf8)))
                    } catch {
                        continue
                    }
                }
            } catch {}
            continuation.finish()
        }
        continuation.onTermination = { _ in reader.cancel() }
        return stream
    }

    public func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        Self.runningPID.withLock { $0 = 0 }
    }

    /// 앱이 끝날 때 부른다(동기). perl은 부모가 죽어도 다음 곡이 바뀔 때까지 남아 있어서 직접 끈다.
    public nonisolated static func terminateRunning() {
        runningPID.withLock { pid in
            if pid > 0 { kill(pid, SIGTERM) }
            pid = 0
        }
    }

    /// 강제로 끝난 앞선 Mactatus가 남긴 perl(같은 스크립트 경로)을 처음 한 번 정리한다.
    private func cleanOrphansOnce() {
        guard !cleanedOrphans else { return }
        cleanedOrphans = true
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", paths.script.path]
        try? pkill.run()
        pkill.waitUntilExit()
    }

    public func send(_ command: MediaCommand) async {
        _ = try? await Command.run("/usr/bin/perl", [paths.script.path, paths.framework.path, "send", "\(command.rawValue)"], timeout: 5)
    }

    /// 재생 위치 옮기기(초)
    public func seek(to seconds: TimeInterval) async {
        let micros = Int(max(seconds, 0) * 1_000_000)
        _ = try? await Command.run("/usr/bin/perl", [paths.script.path, paths.framework.path, "seek", "\(micros)"], timeout: 5)
    }
}
