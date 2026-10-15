// 비공식: Gemini Code Assist(cloudcode-pa) 할당량 API와 Antigravity 로컬 language_server. macOS 27.0.1에서 확인.
import CoreKit
import Foundation

/// Gemini 사용량.
/// 1) Gemini CLI 할당량(`retrieveUserQuota`)을 먼저 시도
/// 2) 지원 종료(UNSUPPORTED_CLIENT, 403 SUBSCRIPTION_REQUIRED)거나 Gemini CLI가 없으면 Antigravity로 전환
public actor GeminiProvider: UsageProvider {
    public nonisolated let id = ProviderID.gemini
    /// Gemini CLI가 지원 종료로 확인되면 12시간 동안 다시 묻지 않는다.
    private var cliUnsupportedUntil: Date?

    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        if (cliUnsupportedUntil ?? .distantPast) < Date() {
            do {
                return try await GeminiCLIQuota.fetch()
            } catch let issue as UsageIssue {
                // 지원 종료면 12시간 동안 건너뛰고, 그 밖의 실패도 Antigravity로 넘어간다
                if issue.kind == .unsupported { cliUnsupportedUntil = Date().addingTimeInterval(12 * 3600) }
            }
        }
        var snapshot = try await AntigravityQuota.fetch()
        if cliUnsupportedUntil != nil { snapshot.notes.append("Gemini CLI 무료 등급이 종료돼 Antigravity 기준으로 보여줘요") }
        return snapshot
    }
}

// MARK: - Gemini CLI

enum GeminiCLIQuota {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini") }
    static let base = "https://cloudcode-pa.googleapis.com/v1internal"

    static func fetch() async throws -> UsageSnapshot {
        guard let data = FileManager.default.contents(atPath: home.appendingPathComponent("oauth_creds.json").path),
              let creds = JSON.object(data), var token = creds["access_token"] as? String else {
            throw UsageIssue.notConfigured("Gemini CLI에 로그인돼 있지 않아요.")
        }
        if let settings = FileManager.default.contents(atPath: home.appendingPathComponent("settings.json").path).flatMap(JSON.object) {
            let auth = ((settings["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String
                ?? settings["selectedAuthType"] as? String
            if let auth, auth != "oauth-personal" { throw UsageIssue.notConfigured("Gemini CLI가 API 키 방식이에요.") }
        }
        let expiry = UsageFormat.epochDate(creds["expiry_date"]) ?? .distantPast
        if expiry.timeIntervalSinceNow < 60 {
            token = try await refresh(refreshToken: creds["refresh_token"] as? String)
        }

        let headers = ["Authorization": "Bearer \(token)"]
        let assist = try await HTTP.send(URL(string: "\(base):loadCodeAssist")!, method: "POST", headers: headers,
                                         json: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
        let assistBody = JSON.object(assist.data) ?? [:]
        if GeminiQuotaParser.isUnsupported(loadCodeAssist: assistBody) {
            throw UsageIssue.unsupported("Gemini CLI 개인 무료 등급은 지원이 종료됐어요.")
        }
        var project = assistBody["cloudaicompanionProject"]
        if let dict = project as? [String: Any] { project = dict["id"] }
        let quota = try await HTTP.send(URL(string: "\(base):retrieveUserQuota")!, method: "POST", headers: headers,
                                        json: (project as? String).map { ["project": $0] } ?? [:])
        if quota.status == 403 { throw UsageIssue.unsupported("Gemini CLI 할당량을 볼 수 있는 구독이 없어요.") }
        guard quota.status == 200 else { throw UsageIssue.failed("Gemini 할당량 API 오류(HTTP \(quota.status))") }
        let tier = (assistBody["paidTier"] as? [String: Any])?["name"] as? String
            ?? (assistBody["currentTier"] as? [String: Any])?["name"] as? String
        return try GeminiQuotaParser.snapshot(fromQuota: quota.data, plan: tier)
    }

    /// Google refresh token은 갱신해도 바뀌지 않으므로 메모리에서만 갱신한다(파일에 쓰지 않음).
    private static func refresh(refreshToken: String?) async throws -> String {
        guard let refreshToken, let client = await cliOAuthClient() else {
            throw UsageIssue.needsAction("Gemini CLI 토큰이 만료됐어요. 터미널에서 gemini를 한 번 실행해 주세요.")
        }
        let response = try await HTTP.send(URL(string: "https://oauth2.googleapis.com/token")!, method: "POST", form: [
            "client_id": client.id, "client_secret": client.secret,
            "refresh_token": refreshToken, "grant_type": "refresh_token",
        ])
        guard response.status == 200, let token = JSON.object(response.data)?["access_token"] as? String else {
            throw UsageIssue.needsAction("Gemini CLI 토큰을 갱신하지 못했어요. 터미널에서 gemini를 한 번 실행해 주세요.")
        }
        return token
    }

    /// 설치된 Gemini CLI 패키지의 oauth2.js에서 OAuth 클라이언트 ID·시크릿(공개 값)을 읽는다.
    private static func cliOAuthClient() async -> (id: String, secret: String)? {
        guard let gemini = await Executables.find("gemini") else { return nil }
        // …/lib/node_modules/@google/gemini-cli/dist/index.js ← bin/gemini 링크
        var dir = URL(fileURLWithPath: gemini).resolvingSymlinksInPath().deletingLastPathComponent()
        while dir.path != "/" && dir.lastPathComponent != "gemini-cli" { dir.deleteLastPathComponent() }
        guard dir.lastPathComponent == "gemini-cli" else { return nil }
        let candidates = [
            dir.appendingPathComponent("node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"),
            dir.deletingLastPathComponent().appendingPathComponent("gemini-cli-core/dist/src/code_assist/oauth2.js"),
        ]
        for file in candidates {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  let id = text.firstMatch(of: /OAUTH_CLIENT_ID\s*=\s*['"]([^'"]+)/)?.1,
                  let secret = text.firstMatch(of: /OAUTH_CLIENT_SECRET\s*=\s*['"]([^'"]+)/)?.1 else { continue }
            return (String(id), String(secret))
        }
        return nil
    }
}

// MARK: - Antigravity

enum AntigravityQuota {
    struct Server { let pid: String; let csrf: String; let ports: [String] }

    static func fetch() async throws -> UsageSnapshot {
        guard let server = await findServer() else {
            throw UsageIssue.needsAction("Antigravity 앱을 켜면 Gemini 한도를 볼 수 있어요.")
        }
        let body: [String: Any] = ["metadata": ["ideName": "antigravity", "extensionName": "antigravity", "locale": "en", "ideVersion": "unknown"]]
        for port in server.ports {
            for scheme in ["http", "https"] {
                let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!
                guard let response = try? await HTTP.send(url, method: "POST", headers: headers(server.csrf), json: body, session: HTTP.localSession),
                      response.status == 200 else { continue }
                let plan = await planName(scheme: scheme, port: port, csrf: server.csrf, body: body)
                return try GeminiQuotaParser.snapshot(fromAntigravitySummary: response.data, plan: plan)
            }
        }
        throw UsageIssue.failed("Antigravity에서 한도 정보를 받지 못했어요.")
    }

    private static func headers(_ csrf: String) -> [String: String] {
        ["X-Codeium-Csrf-Token": csrf, "Connect-Protocol-Version": "1"]
    }

    private static func planName(scheme: String, port: String, csrf: String, body: [String: Any]) async -> String? {
        let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")!
        guard let response = try? await HTTP.send(url, method: "POST", headers: headers(csrf), json: body, session: HTTP.localSession),
              let root = JSON.object(response.data) else { return nil }
        return (((root["userStatus"] as? [String: Any])?["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any])?["planName"] as? String
    }

    /// Antigravity 앱(IDE 아님)의 language_server 프로세스에서 CSRF 토큰과 대기 포트를 찾는다.
    private static func findServer() async -> Server? {
        guard let ps = try? await Command.run("/bin/ps", ["-ax", "-o", "pid=,command="], timeout: 5) else { return nil }
        for line in ps.stdoutText.split(separator: "\n") {
            let text = String(line)
            guard text.contains("language_server"),
                  text.firstMatch(of: /--app_data_dir\s+antigravity(\s|$)/) != nil,
                  let csrf = text.firstMatch(of: /--csrf_token\s+(\S+)/)?.1 else { continue }
            let pid = String(text.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber })
            guard let lsof = try? await Command.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pid], timeout: 5) else { continue }
            let ports = lsof.stdoutText.matches(of: /:(\d+) \(LISTEN\)/).map { String($0.1) }
            if !ports.isEmpty { return Server(pid: pid, csrf: String(csrf), ports: Array(Set(ports)).sorted()) }
        }
        return nil
    }
}

// MARK: - 파서

public enum GeminiQuotaParser {
    /// loadCodeAssist에서 개인 무료 등급 지원 종료 여부.
    public static func isUnsupported(loadCodeAssist root: [String: Any]) -> Bool {
        guard root["currentTier"] == nil, root["paidTier"] == nil else { return false }
        let ineligible = root["ineligibleTiers"] as? [[String: Any]] ?? []
        return ineligible.contains { $0["reasonCode"] as? String == "UNSUPPORTED_CLIENT" }
    }

    /// Gemini CLI `retrieveUserQuota`: 모델마다 가장 적게 남은 버킷을 쓴다.
    public static func snapshot(fromQuota data: Data, plan: String?, now: Date = Date()) throws -> UsageSnapshot {
        guard let buckets = JSON.object(data)?["buckets"] as? [[String: Any]] else {
            throw UsageIssue.failed("Gemini 응답을 읽지 못했어요.")
        }
        var lowest: [String: (fraction: Double, reset: Date?)] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"] as? String, let fraction = JSON.double(bucket["remainingFraction"]) else { continue }
            if fraction < lowest[model]?.fraction ?? .infinity {
                lowest[model] = (fraction, UsageFormat.parseDate(bucket["resetTime"] as? String))
            }
        }
        let windows = lowest.sorted { $0.key < $1.key }.map {
            UsageWindow(id: $0.key, title: $0.key, usedPercent: (1 - $0.value.fraction) * 100, resetsAt: $0.value.reset)
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("Gemini 응답에 한도 정보가 없어요.") }
        return UsageSnapshot(provider: .gemini, source: "Gemini CLI", plan: plan, windows: windows, fetchedAt: now)
    }

    /// Antigravity `RetrieveUserQuotaSummary`: 모델 그룹 × (5시간, 주간).
    public static func snapshot(fromAntigravitySummary data: Data, plan: String?, now: Date = Date()) throws -> UsageSnapshot {
        let root = JSON.object(data)
        guard let groups = ((root?["response"] as? [String: Any]) ?? root)?["groups"] as? [[String: Any]] else {
            throw UsageIssue.failed("Antigravity 응답을 읽지 못했어요.")
        }
        var windows: [UsageWindow] = []
        for group in groups {
            let name = group["displayName"] as? String ?? "모델"
            let short = name.localizedCaseInsensitiveContains("gemini") ? "Gemini"
                : name.localizedCaseInsensitiveContains("claude") ? "Claude·GPT" : name
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                let remaining = JSON.double(bucket["remainingFraction"])
                    ?? JSON.double((bucket["remaining"] as? [String: Any])?["remainingFraction"])
                guard let remaining else { continue }
                let window = switch bucket["window"] as? String {
                case "5h": "5시간"
                case "weekly": "주간"
                case let other?: other
                case nil: bucket["displayName"] as? String ?? "한도"
                }
                windows.append(UsageWindow(id: bucket["bucketId"] as? String ?? "\(short).\(window)", title: "\(short) · \(window)",
                                           usedPercent: (1 - remaining) * 100,
                                           resetsAt: UsageFormat.parseDate(bucket["resetTime"] as? String)))
            }
        }
        guard !windows.isEmpty else { throw UsageIssue.failed("Antigravity 응답에 한도 정보가 없어요.") }
        return UsageSnapshot(provider: .gemini, source: "Antigravity", plan: plan, windows: windows, fetchedAt: now)
    }
}
