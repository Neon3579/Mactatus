import Foundation

public enum UsageFormat {
    /// 한도 창 길이(초) → "5시간", "주간", "30일".
    public static func windowTitle(seconds: Double) -> String {
        let hours = seconds / 3600
        switch hours {
        case 167...169: return "주간"
        case ..<24: return "\(Int(hours.rounded()))시간"
        default:
            let days = Int((hours / 24).rounded())
            return days == 1 ? "하루" : "\(days)일"
        }
    }

    /// "3시간 12분 후 리셋", "2일 4시간 후 리셋", "곧 리셋".
    public static func resetText(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 60 { return "곧 리셋" }
        let minutes = seconds / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        let text: String
        if days > 0 {
            text = hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일"
        } else if hours > 0 {
            text = mins > 0 ? "\(hours)시간 \(mins)분" : "\(hours)시간"
        } else {
            text = "\(mins)분"
        }
        return "\(text) 후 리셋"
    }

    /// 1234567 → "1.2M", 12345 → "12K".
    public static func compactNumber(_ value: Int) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: "\(value / 1000)K"
        case 1000...: String(format: "%.1fK", Double(value) / 1000)
        default: "\(value)"
        }
    }

    /// "pro" → "Pro", "free" → "Free".
    public static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// ISO-8601 날짜(소수점 초 자릿수·시간대 표기가 제각각인 것까지).
    public static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // 소수점 이하 자릿수가 많으면 잘라서 다시 시도
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return plain.date(from: trimmed)
    }

    /// 초 단위 또는 밀리초 단위 epoch → Date.
    public static func epochDate(_ value: Any?) -> Date? {
        guard let number = (value as? NSNumber)?.doubleValue, number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1000 : number)
    }
}

/// JSONSerialization 결과를 다루는 작은 도우미.
enum JSON {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
    }
}
