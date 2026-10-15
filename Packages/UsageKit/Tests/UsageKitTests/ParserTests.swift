import Foundation
import Testing
@testable import UsageKit

/// 0단계에서 받은 실제 응답(개인정보 제거)으로 파서를 확인한다.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private let now = UsageFormat.parseDate("2026-10-15T01:00:00Z")!

@Suite("Claude")
struct ClaudeParserTests {
    @Test func limitsArray() throws {
        let snapshot = try ClaudeUsageParser.snapshot(from: try fixture("claude_usage.json"), plan: "Pro", now: now)
        #expect(snapshot.windows.map(\.title) == ["5시간", "주간"])
        #expect(snapshot.windows.map(\.usedPercent) == [21, 4])
        let reset = try #require(snapshot.windows[0].resetsAt)
        #expect(abs(reset.timeIntervalSince(UsageFormat.parseDate("2026-10-15T05:00:00Z")!)) < 1)
        #expect(snapshot.notes == ["주간 사용 비중: Claude Code 79% · Cowork 21%"])
        #expect(snapshot.mostConstrained?.title == "5시간")
    }

    @Test func legacyFieldsWhenNoLimits() throws {
        let snapshot = try ClaudeUsageParser.snapshot(from: try fixture("claude_usage_legacy.json"), plan: nil, now: now)
        #expect(snapshot.windows.map(\.title) == ["5시간", "주간", "주간 · Opus"])
        #expect(snapshot.windows.map(\.usedPercent) == [63.5, 12, 30])
        #expect(snapshot.windows[2].resetsAt == nil)
    }

    @Test func cliText() throws {
        let text = String(decoding: try fixture("claude_cli_usage.txt"), as: UTF8.self)
        let snapshot = try ClaudeUsageParser.snapshot(fromCLIText: text, plan: "Pro", now: now)
        #expect(snapshot.windows.map(\.title) == ["5시간", "주간"])
        #expect(snapshot.windows.map(\.usedPercent) == [46, 8])
        // Oct 15 2pm Asia/Seoul = 05:00 UTC
        #expect(snapshot.windows[0].resetsAt == UsageFormat.parseDate("2026-10-15T05:00:00Z"))
        #expect(snapshot.windows[1].resetsAt == UsageFormat.parseDate("2026-10-20T06:00:00Z"))
    }

    @Test func emptyResponseFails() {
        #expect(throws: UsageIssue.self) { try ClaudeUsageParser.snapshot(from: Data("{}".utf8), plan: nil) }
    }
}

@Suite("Codex")
struct CodexParserTests {
    @Test func freePlanHasSingleMonthlyWindow() throws {
        let snapshot = try CodexUsageParser.snapshot(fromWham: try fixture("codex_wham_free.json"), now: now)
        #expect(snapshot.plan == "Free")
        #expect(snapshot.windows.map(\.title) == ["30일"])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1794616475))
        #expect(snapshot.notes.isEmpty) // applicable_available_count가 0
    }

    @Test func plusPlanHasSessionAndWeekly() throws {
        let snapshot = try CodexUsageParser.snapshot(fromWham: try fixture("codex_wham_plus.json"), now: now)
        #expect(snapshot.plan == "Plus")
        #expect(snapshot.windows.map(\.title) == ["5시간", "주간"])
        #expect(snapshot.windows.map(\.usedPercent) == [3, 44])
        #expect(snapshot.notes == ["한도 즉시 리셋 쿠폰 1개 사용 가능"])
    }

    @Test func appServerResult() throws {
        let result = try #require(try JSONSerialization.jsonObject(with: try fixture("codex_appserver_free.json")) as? [String: Any])
        let snapshot = try CodexUsageParser.snapshot(fromAppServer: result, now: now)
        #expect(snapshot.windows.map(\.title) == ["30일"])
        #expect(snapshot.plan == "Free")
        #expect(snapshot.notes.contains("무료 리셋 쿠폰 2개 보유"))
    }
}

@Suite("Gemini · Antigravity")
struct GeminiParserTests {
    @Test func antigravitySummary() throws {
        let snapshot = try GeminiQuotaParser.snapshot(fromAntigravitySummary: try fixture("antigravity_summary.json"), plan: "Pro", now: now)
        #expect(snapshot.source == "Antigravity")
        #expect(snapshot.windows.map(\.title) == ["Gemini · 주간", "Gemini · 5시간", "Claude·GPT · 주간", "Claude·GPT · 5시간"])
        #expect(snapshot.windows[1].usedPercent == 25)
        #expect(snapshot.mostConstrained?.id == "gemini-5h")
    }

    @Test func unsupportedClientDetected() throws {
        let root = try #require(try JSONSerialization.jsonObject(with: try fixture("gemini_load_unsupported.json")) as? [String: Any])
        #expect(GeminiQuotaParser.isUnsupported(loadCodeAssist: root))
        #expect(!GeminiQuotaParser.isUnsupported(loadCodeAssist: ["currentTier": ["id": "free-tier"]]))
    }

    @Test func cliQuotaUsesLowestBucketPerModel() throws {
        let snapshot = try GeminiQuotaParser.snapshot(fromQuota: try fixture("gemini_quota.json"), plan: nil, now: now)
        #expect(snapshot.windows.map(\.title) == ["gemini-2.5-flash", "gemini-2.5-pro"])
        #expect(abs(snapshot.windows[1].usedPercent - 40) < 0.001)
    }
}

@Suite("표시 형식")
struct FormatTests {
    @Test(arguments: [(18000.0, "5시간"), (604800, "주간"), (2592000, "30일"), (86400, "하루")])
    func windowTitles(seconds: Double, title: String) {
        #expect(UsageFormat.windowTitle(seconds: seconds) == title)
    }

    @Test func resetTexts() {
        #expect(UsageFormat.resetText(now.addingTimeInterval(3 * 3600 + 12 * 60 + 30), now: now) == "3시간 12분 후 리셋")
        #expect(UsageFormat.resetText(now.addingTimeInterval(2 * 86400 + 4 * 3600), now: now) == "2일 4시간 후 리셋")
        #expect(UsageFormat.resetText(now.addingTimeInterval(30), now: now) == "곧 리셋")
        #expect(UsageFormat.resetText(nil, now: now) == nil)
    }

    @Test func dates() {
        #expect(UsageFormat.parseDate("2026-10-15T04:59:59.805834+00:00") != nil)
        #expect(UsageFormat.parseDate("2026-10-22T00:36:49Z") != nil)
        #expect(UsageFormat.epochDate(1_794_616_475_000 as NSNumber) == Date(timeIntervalSince1970: 1_794_616_475))
    }

    @Test func windowClampsPercent() {
        #expect(UsageWindow(id: "a", title: "a", usedPercent: 130, resetsAt: nil).usedPercent == 100)
    }
}

@Suite("네트워크 오류")
struct NetworkErrorTests {
    @Test func friendlyMessages() {
        #expect(URLError(.timedOut).friendlyMessage(host: "api.anthropic.com") == "api.anthropic.com 응답이 늦어요(시간 초과).")
        #expect(URLError(.notConnectedToInternet).friendlyMessage(host: "x") == "인터넷에 연결돼 있지 않아요.")
    }

    @Test func transientErrorsAreRetried() {
        #expect(URLError(.timedOut).isTransient)
        #expect(URLError(.networkConnectionLost).isTransient)
        #expect(!URLError(.badServerResponse).isTransient)
    }
}
