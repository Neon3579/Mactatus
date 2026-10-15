// 비공식: ChatGPT 백엔드 사용량 API와 `codex app-server` JSON-RPC. macOS 27.0.1 · codex 0.159에서 확인.
import CoreKit
import Foundation

/// Codex 사용량.
/// 1) `~/.codex/auth.json` 토큰으로 `wham/usage` 조회
/// 2) 토큰이 만료됐거나 실패하면 `codex app-server`의 `account/rateLimits/read`(Codex가 직접 토큰을 관리)
/// 토큰은 직접 갱신하지 않는다(OpenAI refresh token은 교체되므로 Codex 로그인이 풀릴 수 있음).
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex

    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let auth = try CodexAuth.read()
        var apiIssue: UsageIssue?
        if let auth, !auth.isExpired {
            do {
                let response = try await HTTP.send(
                    URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                    headers: ["Authorization": "Bearer \(auth.accessToken)", "ChatGPT-Account-Id": auth.accountID ?? ""])
                if response.status == 200 {
                    return try CodexUsageParser.snapshot(fromWham: response.data)
                }
            } catch let issue as UsageIssue {
                apiIssue = issue
            }
        }
        do {
            return try CodexUsageParser.snapshot(fromAppServer: try await CodexAppServer.rateLimits())
        } catch let issue as UsageIssue {
            if auth == nil { throw UsageIssue.notConfigured("Codex에 로그인돼 있지 않아요.") }
            // 두 경로 모두 실패하면 처음 경로의 이유(대개 네트워크)를 보여준다
            throw apiIssue ?? issue
        }
    }
}

// MARK: - auth.json

struct CodexAuth {
    let accessToken: String
    let accountID: String?
    let expiresAt: Date?

    var isExpired: Bool { expiresAt.map { $0.timeIntervalSinceNow < 300 } ?? false }

    static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// 파일이 없거나 API 키 로그인이면 nil.
    static func read() throws -> CodexAuth? {
        guard let data = FileManager.default.contents(atPath: home.appendingPathComponent("auth.json").path),
              let root = JSON.object(data),
              let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { return nil }
        return CodexAuth(accessToken: access, accountID: tokens["account_id"] as? String, expiresAt: jwtExpiry(access))
    }

    private static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let claims = JSON.object(data) else { return nil }
        return UsageFormat.epochDate(claims["exp"])
    }
}

// MARK: - codex app-server

enum CodexAppServer {
    /// npm으로 설치된 codex가 깨져 있을 수 있어 ChatGPT 앱에 들어 있는 것을 먼저 쓴다.
    static func binary() async -> String? {
        await Executables.find("codex", preferring: [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ])
    }

    /// `initialize` → `account/rateLimits/read` 응답의 `result`.
    static func rateLimits(timeout: TimeInterval = 20) async throws -> [String: Any] {
        guard let codex = await binary() else { throw UsageIssue.notConfigured("codex를 찾지 못했어요.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        process.environment = Command.environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let buffer = DataBuffer()
        let found = Signal()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { found.fire(); return }
            buffer.append(chunk)
            if buffer.text.contains(#""id":2"#) { found.fire() }
        }
        do { try process.run() } catch { throw UsageIssue.failed("codex 실행 실패: \(error.localizedDescription)") }
        let box = UncheckedBox(process)
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            if box.value.isRunning { box.value.terminate() }
        }

        func send(_ message: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
            try? input.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
        }
        send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "mactatus", "version": "0.1.0"]]])
        send(["method": "initialized"])
        send(["id": 2, "method": "account/rateLimits/read"])

        let timer = Task.detached { try? await Task.sleep(for: .seconds(timeout)); found.fire() }
        await found.wait()
        timer.cancel()

        for line in buffer.text.split(separator: "\n") {
            guard let message = JSON.object(Data(line.utf8)), (message["id"] as? Int) == 2 else { continue }
            if let result = message["result"] as? [String: Any] { return result }
            let error = (message["error"] as? [String: Any])?["message"] as? String ?? "알 수 없는 오류"
            throw UsageIssue.failed("codex 응답 오류: \(error)")
        }
        throw UsageIssue.failed("codex가 사용량을 돌려주지 않았어요.")
    }
}

// MARK: - 파서

public enum CodexUsageParser {
    /// `wham/usage` 응답.
    public static func snapshot(fromWham data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = JSON.object(data), let limit = root["rate_limit"] as? [String: Any] else {
            throw UsageIssue.failed("Codex 응답을 읽지 못했어요.")
        }
        var windows: [UsageWindow] = []
        for key in ["primary_window", "secondary_window"] {
            if let w = limit[key] as? [String: Any], let window = whamWindow(w, id: key, prefix: nil) { windows.append(window) }
        }
        for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
            let name = extra["limit_name"] as? String ?? extra["limit_id"] as? String
            let inner = extra["rate_limit"] as? [String: Any] ?? extra
            for key in ["primary_window", "secondary_window"] {
                if let w = inner[key] as? [String: Any],
                   let window = whamWindow(w, id: "\(name ?? "extra").\(key)", prefix: name) { windows.append(window) }
            }
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("Codex 응답에 한도 정보가 없어요.") }

        var notes: [String] = []
        if let credits = root["rate_limit_reset_credits"] as? [String: Any],
           let count = credits["applicable_available_count"] as? Int, count > 0 {
            notes.append("한도 즉시 리셋 쿠폰 \(count)개 사용 가능")
        }
        return UsageSnapshot(provider: .codex, source: "Codex", plan: UsageFormat.planName(root["plan_type"] as? String),
                             windows: windows, notes: notes, fetchedAt: now)
    }

    private static func whamWindow(_ w: [String: Any], id: String, prefix: String?) -> UsageWindow? {
        guard let used = JSON.double(w["used_percent"]) else { return nil }
        let seconds = JSON.double(w["limit_window_seconds"])
        let base = seconds.map { UsageFormat.windowTitle(seconds: $0) } ?? "한도"
        return UsageWindow(id: id, title: prefix.map { "\($0) · \(base)" } ?? base, usedPercent: used,
                           resetsAt: UsageFormat.epochDate(w["reset_at"]))
    }

    /// `account/rateLimits/read` 결과.
    public static func snapshot(fromAppServer result: [String: Any], now: Date = Date()) throws -> UsageSnapshot {
        guard let limits = result["rateLimits"] as? [String: Any] else { throw UsageIssue.failed("Codex 응답을 읽지 못했어요.") }
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = limits[key] as? [String: Any], let used = JSON.double(w["usedPercent"]) else { continue }
            let title = JSON.double(w["windowDurationMins"]).map { UsageFormat.windowTitle(seconds: $0 * 60) } ?? "한도"
            windows.append(UsageWindow(id: key, title: title, usedPercent: used, resetsAt: UsageFormat.epochDate(w["resetsAt"])))
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("Codex 응답에 한도 정보가 없어요.") }
        var notes = ["codex app-server 기준"]
        if let count = (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int, count > 0 {
            notes.append("무료 리셋 쿠폰 \(count)개 보유")
        }
        return UsageSnapshot(provider: .codex, source: "Codex", plan: UsageFormat.planName(limits["planType"] as? String),
                             windows: windows, notes: notes, fetchedAt: now)
    }
}
