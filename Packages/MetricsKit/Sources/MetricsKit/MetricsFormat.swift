import Foundation

public enum MetricsFormat {
    /// 메모리: 1024 기준("8.0 GB", "512 MB").
    public static func memory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: gb >= 10 ? "%.0f GB" : "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    /// 저장 공간: Finder처럼 1000 기준("245 GB", "1.2 TB").
    public static func storage(_ bytes: Int64) -> String {
        let value = Double(bytes)
        switch value {
        case 1e12...: return String(format: "%.1f TB", value / 1e12)
        case 1e9...: return String(format: "%.0f GB", value / 1e9)
        default: return String(format: "%.0f MB", value / 1e6)
        }
    }

    /// 초당 바이트 → "1.2 MB/s", "340 KB/s", "0 KB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case 1e9...: return String(format: "%.1f GB/s", bytesPerSecond / 1e9)
        case 1e6...: return String(format: bytesPerSecond >= 1e8 ? "%.0f MB/s" : "%.1f MB/s", bytesPerSecond / 1e6)
        default: return String(format: "%.0f KB/s", bytesPerSecond / 1e3)
        }
    }

    /// 0~1 → "37%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// 분 → "2시간 54분", "45분".
    public static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)분" }
        return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
    }
}
