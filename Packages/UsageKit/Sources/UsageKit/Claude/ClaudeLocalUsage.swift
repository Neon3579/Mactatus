import Foundation

/// Claude Code 로컬 로그(JSONL)에서 오늘 쓴 토큰을 센다. 대화 내용은 읽지 않고 `usage`만 본다.
/// 바뀐 파일만 다시 읽도록 파일별 결과를 캐시한다.
actor ClaudeLocalUsage {
    private struct FileTotals {
        var modified: Date
        var day: Date
        var outputTokens = 0
        var inputTokens = 0
        var messages = 0
        var seen: Set<String> = []
    }

    private var cache: [String: FileTotals] = [:]

    func todayNotes(now: Date = Date()) -> [String] {
        let today = Calendar.current.startOfDay(for: now)
        let fm = FileManager.default
        var output = 0, input = 0, messages = 0
        var live: Set<String> = []

        for path in Self.recentLogFiles(since: today) {
            live.insert(path)
            guard let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
            if let cached = cache[path], cached.modified == modified, cached.day == today {
                output += cached.outputTokens; input += cached.inputTokens; messages += cached.messages
                continue
            }
            let totals = Self.read(path: path, modified: modified, today: today)
            cache[path] = totals
            output += totals.outputTokens; input += totals.inputTokens; messages += totals.messages
        }
        cache = cache.filter { live.contains($0.key) }
        guard messages > 0 else { return [] }
        return ["오늘: 응답 \(messages)개 · 입력 \(UsageFormat.compactNumber(input)) · 출력 \(UsageFormat.compactNumber(output)) 토큰"]
    }

    private static func read(path: String, modified: Date, today: Date) -> FileTotals {
        var totals = FileTotals(modified: modified, day: today)
        guard let data = FileManager.default.contents(atPath: path) else { return totals }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for line in data.split(separator: UInt8(ascii: "\n")) where line.count > 20 {
            // 빠른 걸러내기: usage가 없는 줄은 JSON을 풀지 않는다
            guard line.firstRange(of: Data(#""usage""#.utf8)) != nil,
                  let row = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  row["type"] as? String == "assistant",
                  let message = row["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let stamp = (row["timestamp"] as? String).flatMap(iso.date(from:)),
                  stamp >= today else { continue }
            let key = "\(message["id"] as? String ?? "")|\(row["requestId"] as? String ?? "")"
            guard totals.seen.insert(key).inserted else { continue }
            totals.outputTokens += (usage["output_tokens"] as? Int) ?? 0
            totals.inputTokens += ((usage["input_tokens"] as? Int) ?? 0) + ((usage["cache_creation_input_tokens"] as? Int) ?? 0)
            totals.messages += 1
        }
        return totals
    }

    /// CLI와 데스크톱 앱 세션 로그 중 오늘 수정된 파일.
    private static func recentLogFiles(since day: Date) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var roots = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
        let appSupport = home.appendingPathComponent("Library/Application Support/Claude")
        for sub in ["local-agent-mode-sessions", "claude-code-sessions"] {
            roots += findProjectDirs(under: appSupport.appendingPathComponent(sub))
        }
        var files: [String] = []
        for root in roots {
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = values?.contentModificationDate, modified >= day { files.append(url.path) }
            }
        }
        return files
    }

    /// 데스크톱 앱 세션 폴더 안의 `.claude/projects`들.
    private static func findProjectDirs(under base: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in walker where url.lastPathComponent == "projects" && url.deletingLastPathComponent().lastPathComponent == ".claude" {
            result.append(url)
            walker.skipDescendants()
        }
        return result
    }
}
