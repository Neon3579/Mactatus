import Foundation
import os

public enum Log {
    public static let usage = Logger(subsystem: "app.mactatus", category: "usage")
    public static let app = Logger(subsystem: "app.mactatus", category: "app")
}

public struct CommandResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    public let timedOut: Bool

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum CommandError: Error, LocalizedError {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message): "실행 실패: \(message)"
        }
    }
}

/// 다른 실행 파일을 띄우고 끝날 때까지(또는 시간 초과까지) 기다린다.
public enum Command {
    /// GUI 앱은 셸 PATH를 물려받지 않으므로 자주 쓰는 경로를 붙여 준다.
    public static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = (extra + (env["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        return env
    }

    public static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 20,
        currentDirectory: URL? = nil
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let exit = Signal()
        process.terminationHandler = { _ in exit.fire() }
        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed("\(executable): \(error.localizedDescription)")
        }

        let box = UncheckedBox(process)
        let timedOut = Flag()
        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            if box.value.isRunning {
                timedOut.set()
                box.value.terminate()
            }
        }
        async let stdout = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderr = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let (o, e) = await (stdout, stderr)
        await exit.wait()
        watchdog.cancel()
        return CommandResult(status: process.terminationStatus, stdout: o, stderr: e, timedOut: timedOut.isSet)
    }
}

/// 실행 파일 찾기: 흔한 설치 위치 → 로그인 셸의 `command -v` 순서.
public enum Executables {
    public static func find(_ name: String, preferring candidates: [String] = []) async -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let dirs = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(home)/.npm-global/bin", "\(home)/bin"]
        for path in candidates + dirs.map({ "\($0)/\(name)" }) where fm.isExecutableFile(atPath: path) {
            return path
        }
        guard let result = try? await Command.run("/bin/zsh", ["-lc", "command -v \(name)"], timeout: 5),
              result.status == 0 else { return nil }
        let path = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        return fm.isExecutableFile(atPath: path) ? path : nil
    }
}

// MARK: - 동시성 도우미

/// 한 번만 울리는 신호. 먼저 울려도, 나중에 기다려도 안전하다.
public final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func fire() {
        let pending: [CheckedContinuation<Void, Never>] = lock.withLock {
            fired = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    public func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock {
                if fired { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

public final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func set() { lock.withLock { value = true } }
    public var isSet: Bool { lock.withLock { value } }
}

/// 잠금으로 보호되는 데이터 버퍼.
public final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    public init() {}
    public func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    public var value: Data { lock.withLock { data } }
    public var text: String { String(decoding: value, as: UTF8.self) }
}

/// Sendable이 아닌 Foundation 객체(Process 등)를 정해진 방식으로만 넘길 때 쓴다.
public final class UncheckedBox<T>: @unchecked Sendable {
    public let value: T
    public init(_ value: T) { self.value = value }
}
