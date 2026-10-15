// 비공식: Claude Code OAuth 사용량 API와 `claude -p /usage` 출력. macOS 27.0.1 · Claude Code 2.1.294에서 확인.
import CoreKit
import Foundation

/// Claude Code 사용량.
/// 1) 키체인 토큰으로 사용량 API 조회
/// 2) 토큰이 만료됐으면 `claude -p /usage`(모델 요청 없음)로 읽는다 — 이때 Claude Code가 토큰도 갱신한다.
/// 토큰은 직접 갱신하지 않는다(Claude Code가 refresh token을 교체하므로 로그인이 풀릴 수 있음).
public actor ClaudeProvider: UsageProvider {
    public nonisolated let id = ProviderID.claude
    private let allowCLI: @Sendable () async -> Bool
    private let localUsage = ClaudeLocalUsage()
    private var lastCLIRun: Date?

    /// - Parameter allowCLI: 토큰 만료 시 `claude`를 백그라운드로 실행해도 되는지(설정값).
    public init(allowCLI: @escaping @Sendable () async -> Bool) {
        self.allowCLI = allowCLI
    }

    public func fetch() async throws -> UsageSnapshot {
        var oauth = try await ClaudeKeychain.read()
        var cliSnapshot: UsageSnapshot?

        if oauth.isExpired {
            cliSnapshot = try await runCLIUsage(plan: oauth.plan)
            oauth = (try? await ClaudeKeychain.read()) ?? oauth
        }

        if !oauth.isExpired {
            switch try await ClaudeAPI.usage(token: oauth.accessToken) {
            case .success(let data):
                var snapshot = try ClaudeUsageParser.snapshot(from: data, plan: oauth.plan)
                snapshot.notes += await localUsage.todayNotes()
                return snapshot
            case .unauthorized:
                if cliSnapshot == nil { cliSnapshot = try await runCLIUsage(plan: oauth.plan) }
            }
        }

        guard var snapshot = cliSnapshot else {
            throw UsageIssue.needsAction("Claude Code 로그인이 만료됐어요. 터미널에서 claude를 한 번 실행해 주세요.")
        }
        snapshot.notes += await localUsage.todayNotes()
        return snapshot
    }

    /// `claude -p /usage`는 30분에 한 번까지만 실행한다.
    private func runCLIUsage(plan: String?) async throws -> UsageSnapshot? {
        guard await allowCLI() else {
            throw UsageIssue.needsAction("Claude Code 토큰이 만료됐어요. 터미널에서 claude를 한 번 실행하거나, 설정에서 자동 갱신을 켜 주세요.")
        }
        if let last = lastCLIRun, Date().timeIntervalSince(last) < 30 * 60 { return nil }
        lastCLIRun = Date()
        return try await ClaudeCLI.usage(plan: plan)
    }
}

// MARK: - 키체인

struct ClaudeOAuth: Sendable {
    let accessToken: String
    let expiresAt: Date
    let subscriptionType: String?

    var isExpired: Bool { expiresAt.timeIntervalSinceNow < 60 }
    var plan: String? { UsageFormat.planName(subscriptionType) }
}

enum ClaudeKeychain {
    /// `/usr/bin/security`로 읽는다(Claude Code가 같은 도구로 저장하므로 확인 창이 뜨지 않음).
    static func read() async throws -> ClaudeOAuth {
        let result = try await Command.run(
            "/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], timeout: 10)
        guard result.status == 0,
              let root = JSON.object(result.stdout),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              let expires = JSON.double(oauth["expiresAt"]) else {
            throw UsageIssue.notConfigured("Claude Code에 로그인돼 있지 않아요.")
        }
        return ClaudeOAuth(
            accessToken: token,
            expiresAt: Date(timeIntervalSince1970: expires / 1000),
            subscriptionType: oauth["subscriptionType"] as? String)
    }
}

// MARK: - 사용량 API

enum ClaudeAPI {
    enum Result { case success(Data), unauthorized }

    static func usage(token: String) async throws -> Result {
        let response = try await HTTP.send(
            URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            headers: [
                "Authorization": "Bearer \(token)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
            ])
        switch response.status {
        case 200: return .success(response.data)
        case 401, 403: return .unauthorized
        default: throw UsageIssue.failed("Claude 사용량 API 오류(HTTP \(response.status))")
        }
    }
}

// MARK: - claude -p /usage

enum ClaudeCLI {
    static func usage(plan: String?) async throws -> UsageSnapshot {
        guard let claude = await Executables.find("claude") else {
            throw UsageIssue.notConfigured("claude 명령을 찾지 못했어요.")
        }
        let workDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mactatus/ClaudeProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let result = try await Command.run(
            claude,
            ["-p", "/usage", "--output-format", "json", "--no-session-persistence",
             "--strict-mcp-config", "--settings", #"{"disableAllHooks":true}"#],
            timeout: 60, currentDirectory: workDir)
        guard result.status == 0, let root = JSON.object(result.stdout), let text = root["result"] as? String else {
            throw UsageIssue.failed(result.timedOut ? "claude /usage 응답이 너무 늦어요." : "claude /usage 실행에 실패했어요.")
        }
        return try ClaudeUsageParser.snapshot(fromCLIText: text, plan: plan)
    }
}

// MARK: - 파서

public enum ClaudeUsageParser {
    /// 사용량 API 응답 → 스냅샷. `limits[]`가 있으면 그것을, 없으면 `five_hour`/`seven_day`를 쓴다.
    public static func snapshot(from data: Data, plan: String?, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = JSON.object(data) else { throw UsageIssue.failed("Claude 응답을 읽지 못했어요.") }
        var windows: [UsageWindow] = []

        if let limits = root["limits"] as? [[String: Any]], !limits.isEmpty {
            for limit in limits {
                guard let percent = JSON.double(limit["percent"]) else { continue }
                let kind = limit["kind"] as? String ?? "limit"
                let group = limit["group"] as? String
                let scope = limit["scope"] as? String
                var title = switch group {
                case "session": "5시간"
                case "weekly": "주간"
                default: kind
                }
                if let scope, !scope.isEmpty { title += " · \(scope)" }
                windows.append(UsageWindow(id: kind + (scope.map { ".\($0)" } ?? ""), title: title,
                                           usedPercent: percent, resetsAt: UsageFormat.parseDate(limit["resets_at"] as? String)))
            }
        } else {
            let known: [(String, String)] = [("five_hour", "5시간"), ("seven_day", "주간"),
                                             ("seven_day_opus", "주간 · Opus"), ("seven_day_sonnet", "주간 · Sonnet")]
            for (key, title) in known {
                guard let window = root[key] as? [String: Any], let used = JSON.double(window["utilization"]) else { continue }
                windows.append(UsageWindow(id: key, title: title, usedPercent: used,
                                           resetsAt: UsageFormat.parseDate(window["resets_at"] as? String)))
            }
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("Claude 응답에 한도 정보가 없어요.") }

        var notes: [String] = []
        if let rows = (root["seven_day_breakdown"] as? [String: Any])?["rows"] as? [[String: Any]] {
            let parts = rows.compactMap { row -> String? in
                guard let name = row["display_name"] as? String, let percent = JSON.double(row["percent"]), percent > 0 else { return nil }
                return "\(name) \(Int(percent))%"
            }
            if !parts.isEmpty { notes.append("주간 사용 비중: " + parts.joined(separator: " · ")) }
        }
        return UsageSnapshot(provider: .claude, source: "Claude Code", plan: plan, windows: windows, notes: notes, fetchedAt: now)
    }

    /// `claude -p /usage` 텍스트 → 스냅샷.
    /// 예: "Current session: 46% used · resets Oct 15 at 2pm (Asia/Seoul)"
    public static func snapshot(fromCLIText text: String, plan: String?, now: Date = Date()) throws -> UsageSnapshot {
        let pattern = #"Current (session|week)(?: \(([^)]*)\))?:\s*([\d.]+)% used(?:\s*·\s*resets ([^\n]+))?"#
        let regex = try NSRegularExpression(pattern: pattern)
        var windows: [UsageWindow] = []
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = match.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let kind = group(1), let percent = group(3).flatMap(Double.init) else { continue }
            let scope = group(2).flatMap { $0 == "all models" ? nil : $0 }
            var title = kind == "session" ? "5시간" : "주간"
            if let scope { title += " · \(scope)" }
            windows.append(UsageWindow(id: "cli.\(kind).\(scope ?? "all")", title: title, usedPercent: percent,
                                       resetsAt: parseCLIReset(group(4), now: now)))
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("claude /usage 출력에서 한도를 찾지 못했어요.") }
        return UsageSnapshot(provider: .claude, source: "Claude Code", plan: plan, windows: windows,
                             notes: ["claude /usage 기준"], fetchedAt: now)
    }

    /// "Oct 15 at 2pm (Asia/Seoul)", "Oct 20 at 3:30pm (Asia/Seoul)", "2pm (Asia/Seoul)" → Date.
    static func parseCLIReset(_ text: String?, now: Date) -> Date? {
        guard var text = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        var timeZone = TimeZone.current
        if let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            timeZone = TimeZone(identifier: String(text[text.index(after: open)..<close])) ?? timeZone
            text = text[..<open].trimmingCharacters(in: .whitespaces)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let year = calendar.component(.year, from: now)

        for format in ["MMM d 'at' ha", "MMM d 'at' h:mma", "MMM d"] {
            formatter.dateFormat = "yyyy " + format
            if var date = formatter.date(from: "\(year) \(text)") {
                if date < now.addingTimeInterval(-86400) { date = calendar.date(byAdding: .year, value: 1, to: date) ?? date }
                return date
            }
        }
        for format in ["ha", "h:mma"] {
            formatter.dateFormat = "yyyy-MM-dd " + format
            let day = DateFormatter()
            day.locale = formatter.locale
            day.timeZone = timeZone
            day.dateFormat = "yyyy-MM-dd"
            if var date = formatter.date(from: "\(day.string(from: now)) \(text)") {
                if date < now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
                return date
            }
        }
        return nil
    }
}
